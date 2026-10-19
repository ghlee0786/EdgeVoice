using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;

namespace EdgeVoice.Agent.Desktop;

/// <summary>백엔드가 속한 docker compose 프로젝트: 이름 · 폴더 · compose 파일들.</summary>
public sealed record ComposeProject(string Name, string Folder, IReadOnlyList<string> Files);

/// <summary>
/// 이 PC 의 docker 로 백엔드와 같은 compose 프로젝트를 다룬다 — 서비스 다시 만들기, GPU 서비스 끄기·켜기(VRAM 비우기).
/// 백엔드 포트를 publish 한 컨테이너의 compose 라벨(프로젝트·폴더·파일)로 같은 프로젝트를 찾으므로
/// 백엔드가 이 PC 의 docker 에 없으면(원격·테스트용 가짜 백엔드) 아무것도 실행하지 않는다.
/// </summary>
public static class HostCompose
{
    /// <summary>VRAM 을 쓰는 서비스 (vision 은 separate-vision 프로필로 켰을 때만 있다).</summary>
    public static IReadOnlyList<string> GpuServices { get; } = new[] { "llm", "stt", "tts", "embedding", "vision" };

    /// <summary>다시 켤 서비스 (vision 은 프로필 서비스라 따로 켜지 않는다).</summary>
    public static IReadOnlyList<string> GpuServicesToStart { get; } = new[] { "llm", "stt", "tts", "embedding" };

    /// <returns>다시 만들었으면 null, 못 했으면 이유.</returns>
    public static async Task<string?> RestartAsync(Uri backend, string service)
    {
        if (!backend.IsLoopback)
        {
            return "백엔드가 이 PC 에 있지 않아 다시 만들 수 없습니다";
        }

        try
        {
            if (await FindAsync(backend) is not { } project)
            {
                return "이 PC 의 docker 에서 백엔드 컨테이너를 찾지 못했습니다";
            }

            var (exit, output) = await RunAsync(Args(project, "up", "-d", service));
            return exit == 0 ? null : output.Trim();
        }
        catch (Exception ex)
        {
            // docker 가 설치되어 있지 않은 PC
            return ex.Message;
        }
    }

    /// <summary>백엔드가 이 PC 의 docker 에 있으면 그 compose 프로젝트, 아니면 null (docker 가 없어도 null).</summary>
    public static async Task<ComposeProject?> FindAsync(Uri backend)
    {
        if (!backend.IsLoopback)
        {
            return null;
        }

        try
        {
            var (_, found) = await RunAsync("ps", "--filter", $"publish={backend.Port}", "--format",
                "{{.Label \"com.docker.compose.project\"}}|{{.Label \"com.docker.compose.project.working_dir\"}}|{{.Label \"com.docker.compose.project.config_files\"}}");
            return ParseLabels(found);
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// <summary>docker ps 의 '프로젝트|폴더|파일,파일' 한 줄 → 프로젝트.</summary>
    public static ComposeProject? ParseLabels(string output)
        => output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .FirstOrDefault()?.Split('|') is [{ Length: > 0 } project, { Length: > 0 } folder, { Length: > 0 } files]
            ? new ComposeProject(project, folder, files.Split(','))
            : null;

    /// <summary>docker 에 넘길 인자: compose -p 프로젝트 --project-directory 폴더 -f 파일… 명령….</summary>
    public static string[] Args(ComposeProject project, params string[] command)
    {
        var args = new List<string> { "compose", "-p", project.Name, "--project-directory", project.Folder };
        foreach (var file in project.Files)
        {
            args.Add("-f");
            args.Add(file);
        }

        args.AddRange(command);
        return args.ToArray();
    }

    /// <summary>켜져 있는 서비스 중 끌 GPU 서비스 (켜져 있지 않은 vision 을 끄라고 하면 compose 가 오류를 낸다).</summary>
    public static string[] StopArgs(ComposeProject project, IEnumerable<string> running)
    {
        var set = running.ToHashSet();
        return Args(project, new[] { "stop" }.Concat(GpuServices.Where(set.Contains)).ToArray());
    }

    public static string[] StartArgs(ComposeProject project)
        => Args(project, new[] { "up", "-d" }.Concat(GpuServicesToStart).ToArray());

    /// <summary>'서비스|health' 줄들에서 다시 켤 GPU 서비스가 모두 healthy 인지.</summary>
    public static bool AllHealthy(string psOutput)
    {
        var health = psOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(line => line.Split('|'))
            .Where(p => p.Length == 2)
            .ToDictionary(p => p[0], p => p[1]);
        return GpuServicesToStart.All(s => health.GetValueOrDefault(s) == "healthy");
    }

    /// <summary>지금 켜져 있는 서비스 이름들.</summary>
    public static async Task<IReadOnlyList<string>> RunningAsync(ComposeProject project)
    {
        var (_, output) = await RunAsync(Args(project, "ps", "--services", "--status", "running"));
        return output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    }

    /// <returns>끝났으면 null, 못 했으면 이유.</returns>
    public static async Task<string?> StopGpuAsync(ComposeProject project)
    {
        var args = StopArgs(project, await RunningAsync(project));
        if (args[^1] == "stop")
        {
            return null; // 이미 다 꺼져 있다
        }

        var (exit, output) = await RunAsync(args);
        return exit == 0 ? null : output.Trim();
    }

    public static async Task<string?> StartGpuAsync(ComposeProject project)
    {
        var (exit, output) = await RunAsync(StartArgs(project));
        return exit == 0 ? null : output.Trim();
    }

    public static async Task<bool> GpuHealthyAsync(ComposeProject project)
    {
        var (_, output) = await RunAsync(Args(project, "ps", "--format", "{{.Service}}|{{.Health}}"));
        return AllHealthy(output);
    }

    private static async Task<(int Exit, string Output)> RunAsync(params string[] args)
    {
        var info = new ProcessStartInfo("docker")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (var arg in args)
        {
            info.ArgumentList.Add(arg);
        }

        using var process = Process.Start(info)!;
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        return (process.ExitCode, await stdout + await stderr);
    }
}
