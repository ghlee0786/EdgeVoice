using Avalonia.Headless.XUnit;
using EdgeVoice.Agent.Core;
using Xunit;

namespace EdgeVoice.Agent.Desktop.Tests;

/// <summary>
/// AI 서비스 끄기·켜기(VRAM 비우기, 사용자 요청 2026-10-19: 선택식). 실제 컨테이너는 내리지 않고 compose 명령만 확인한다.
/// </summary>
public class AiServicesTests
{
    private static readonly ComposeProject Project = new("edgevoice", @"C:\EdgeVoice\server", new[] { @"C:\EdgeVoice\server\docker-compose.yml" });

    private static readonly string[] Prefix =
        { "compose", "-p", "edgevoice", "--project-directory", @"C:\EdgeVoice\server", "-f", @"C:\EdgeVoice\server\docker-compose.yml" };

    [Fact]
    public void 백엔드_컨테이너_라벨에서_compose_프로젝트를_찾는다()
    {
        var project = HostCompose.ParseLabels("ai-agent|C:\\work\\ai|C:\\work\\ai\\docker-compose.dev.yml,C:\\work\\ai\\x.yml\n");

        Assert.NotNull(project);
        Assert.Equal("ai-agent", project.Name);
        Assert.Equal(new[] { @"C:\work\ai\docker-compose.dev.yml", @"C:\work\ai\x.yml" }, project.Files);
        Assert.Null(HostCompose.ParseLabels(""));
        Assert.Null(HostCompose.ParseLabels("||"));
    }

    [Fact]
    public void 끄기는_켜져_있는_GPU_서비스만_stop_한다()
    {
        var args = HostCompose.StopArgs(Project, new[] { "backend", "llm", "stt", "tts", "embedding", "redis" });

        Assert.Equal(Prefix.Concat(new[] { "stop", "llm", "stt", "tts", "embedding" }), args);
    }

    [Fact]
    public void vision_은_켜져_있을_때만_함께_끈다()
    {
        Assert.Equal(Prefix.Concat(new[] { "stop", "llm", "vision" }), HostCompose.StopArgs(Project, new[] { "llm", "vision" }));
    }

    [Fact]
    public void 켜기는_GPU_서비스를_up_d_로_올린다()
    {
        Assert.Equal(Prefix.Concat(new[] { "up", "-d", "llm", "stt", "tts", "embedding" }), HostCompose.StartArgs(Project));
    }

    [Fact]
    public void 네_GPU_서비스가_모두_healthy_여야_준비된_것이다()
    {
        Assert.True(HostCompose.AllHealthy("llm|healthy\nstt|healthy\ntts|healthy\nembedding|healthy\nredis|healthy\n"));
        Assert.False(HostCompose.AllHealthy("llm|starting\nstt|healthy\ntts|healthy\nembedding|healthy\n"));
        Assert.False(HostCompose.AllHealthy("stt|healthy\ntts|healthy\nembedding|healthy\n"));
    }

    [Fact]
    public void 종료_때_끄기_옵션은_기본_꺼짐이고_켰을_때만_끈다()
    {
        Assert.False(new EdgeVoiceOptions().StopAiServicesOnExit);
        Assert.False(AiServices.ShouldStopOnExit(new EdgeVoiceOptions(), null));
        Assert.False(AiServices.ShouldStopOnExit(new EdgeVoiceOptions { StopAiServicesOnExit = true }, null));
    }

    [Fact]
    public async Task 원격_백엔드면_AI_서비스_메뉴를_만들지_않는다()
    {
        Assert.Null(await AiServices.FindAsync(new Uri("http://192.168.0.20:11000")));
    }

    [AvaloniaFact]
    public async Task 설정에서_종료할_때_끄기를_켜고_저장하면_파일과_실행_중인_옵션이_바뀐다()
    {
        using var s = new Scenario();
        var settings = s.Main.Settings;
        var path = Path.Combine(Directory.CreateTempSubdirectory().FullName, "appsettings.json");
        settings.UserSettingsPath = path;
        await Scenario.WaitUntil(() => settings.ContextWindowSize == 10);
        Assert.False(settings.StopAiServicesOnExit);

        settings.StopAiServicesOnExit = true;
        settings.SaveCommand.Execute();
        await Scenario.WaitUntil(() => !settings.HasChanges);

        Assert.True(UserSettings.Load(path, path).StopAiServicesOnExit);
        Assert.True(UserSettings.Load(path, path).CheckForUpdates);
        Assert.True(Autofac.ResolutionExtensions.Resolve<EdgeVoiceOptions>(s.Container).StopAiServicesOnExit);
    }
}
