using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;

namespace EdgeVoice.Agent.Desktop;

/// <summary>새 릴리스: 버전, 태그, 설치 프로그램 자산 주소.</summary>
public sealed record ReleaseInfo(Version Version, string Tag, string InstallerUrl);

/// <summary>
/// GitHub Releases 의 최신 릴리스를 보고, 지금 버전보다 새것이면 설치 프로그램(EdgeVoice-Setup-*.exe)을 받아 조용히 실행한다.
/// 설치 프로그램이 실행 중인 앱을 닫고 기존 파일을 지운 뒤 새로 깔고 앱을 다시 띄운다(clients/dotnet/installer/EdgeVoice.iss).
/// </summary>
public static class UpdateChecker
{
    /// <summary>릴리스를 올리는 GitHub 저장소(소유자/이름). 저장소 이름이 바뀌면 여기만 고친다.</summary>
    public const string Repository = "ghlee0786/EdgeVoice";

    /// <summary>이 앱의 버전 (릴리스 빌드는 태그에서 -p:Version= 으로 넣는다. 0.0.0 = 개발 빌드).</summary>
    public static Version Current { get; } = Normalize(typeof(UpdateChecker).Assembly.GetName().Version ?? new Version(0, 0, 0));

    /// <summary>개발 빌드(소스에서 실행)는 확인하지 않는다 — 릴리스로 덮어쓰지 않게.</summary>
    public static bool IsDevBuild => Current == new Version(0, 0, 0);

    /// <summary>'v1.2.3' · '1.2.3-beta' → 1.2.3. 버전 꼴이 아니면 null.</summary>
    public static Version? ParseTag(string? tag)
    {
        var text = (tag ?? "").Trim().TrimStart('v', 'V').Split('-', '+')[0];
        return Version.TryParse(text, out var version) ? Normalize(version) : null;
    }

    /// <summary>최신 릴리스 응답(api.github.com/repos/…/releases/latest)이 지금보다 새것이고 설치 프로그램이 있으면 그 정보.</summary>
    public static ReleaseInfo? Newer(JsonNode? release, Version current)
    {
        var tag = release?["tag_name"]?.ToString();
        if (release?["draft"]?.GetValue<bool>() == true || release?["prerelease"]?.GetValue<bool>() == true
            || ParseTag(tag) is not { } version || version <= current)
        {
            return null;
        }

        var url = (release?["assets"]?.AsArray() ?? new JsonArray())
            .Select(a => (Name: a?["name"]?.ToString() ?? "", Url: a?["browser_download_url"]?.ToString()))
            .FirstOrDefault(a => a.Name.Contains("-Setup-", StringComparison.OrdinalIgnoreCase)
                                 && a.Name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)).Url;
        return url is null ? null : new ReleaseInfo(version, tag!, url);
    }

    public static HttpClient CreateClient()
    {
        var http = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        // GitHub API 는 User-Agent 가 없으면 거절한다
        http.DefaultRequestHeaders.UserAgent.ParseAdd($"EdgeVoice-Agent/{Current}");
        return http;
    }

    /// <summary>새 릴리스가 있으면 그 정보. 없거나 확인하지 못하면(오프라인·저장소 없음) null.</summary>
    public static async Task<ReleaseInfo?> FindNewerAsync(HttpClient http)
    {
        try
        {
            var release = await http.GetFromJsonAsync<JsonNode>($"https://api.github.com/repos/{Repository}/releases/latest");
            return Newer(release, Current);
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException)
        {
            return null;
        }
    }

    /// <summary>설치 프로그램을 임시 폴더에 받아 조용히 실행한다. 실행하면 앱을 끝내야 한다(설치 프로그램이 다시 띄운다).</summary>
    public static async Task InstallAsync(HttpClient http, ReleaseInfo release)
    {
        var path = Path.Combine(Path.GetTempPath(), Path.GetFileName(new Uri(release.InstallerUrl).LocalPath));
        await using (var file = File.Create(path))
        {
            await using var download = await http.GetStreamAsync(release.InstallerUrl);
            await download.CopyToAsync(file);
        }

        // /SILENT: 진행 막대만 보인다. 마법사에서 넣은 설정은 사용자 설정 파일에 남아 있어 다시 묻지 않는다
        Process.Start(new ProcessStartInfo(path, "/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS")
        {
            UseShellExecute = true,
        });
    }

    private static Version Normalize(Version v) => new(v.Major, v.Minor, Math.Max(v.Build, 0));
}
