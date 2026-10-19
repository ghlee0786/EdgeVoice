using System.Text.Json.Nodes;
using Avalonia.Headless.XUnit;
using Xunit;

namespace EdgeVoice.Agent.Desktop.Tests;

/// <summary>
/// 자동 업데이트(사용자 요청 2026-10-19): GitHub 최신 릴리스가 새 버전이면 설치 프로그램 자산을 고르고,
/// 설정 탭의 '업데이트 자동 확인' 은 이 PC 의 사용자 설정 파일(설치 마법사와 같은 파일)에 저장된다.
/// </summary>
public class UpdateScenarioTests
{
    private static JsonNode Release(string tag, params string[] assets) => new JsonObject
    {
        ["tag_name"] = tag,
        ["assets"] = new JsonArray(assets.Select(name => (JsonNode)new JsonObject
        {
            ["name"] = name,
            ["browser_download_url"] = $"https://github.com/o/r/releases/download/{tag}/{name}",
        }).ToArray()),
    };

    [Theory]
    [InlineData("v1.2.3", "1.2.3")]
    [InlineData("1.2", "1.2.0")]
    [InlineData("v2.0.0-beta.1", "2.0.0")]
    [InlineData("latest", null)]
    public void 태그에서_버전을_읽는다(string tag, string? expected)
        => Assert.Equal(expected, UpdateChecker.ParseTag(tag)?.ToString());

    [Fact]
    public void 새_버전이면_설치_프로그램_자산을_고른다()
    {
        var release = Release("v1.3.0", "EdgeVoice.Agent-v1.3.0-win-x64.zip", "EdgeVoice-Setup-1.3.0.exe");

        var found = UpdateChecker.Newer(release, new Version(1, 2, 0));

        Assert.NotNull(found);
        Assert.Equal(new Version(1, 3, 0), found.Version);
        Assert.EndsWith("/EdgeVoice-Setup-1.3.0.exe", found.InstallerUrl);
    }

    [Fact]
    public void 같거나_옛_버전이거나_설치_프로그램이_없으면_묻지_않는다()
    {
        Assert.Null(UpdateChecker.Newer(Release("v1.2.0", "EdgeVoice-Setup-1.2.0.exe"), new Version(1, 2, 0)));
        Assert.Null(UpdateChecker.Newer(Release("v1.1.0", "EdgeVoice-Setup-1.1.0.exe"), new Version(1, 2, 0)));
        Assert.Null(UpdateChecker.Newer(Release("v1.3.0", "EdgeVoice.Agent-v1.3.0-win-x64.zip"), new Version(1, 2, 0)));
        var pre = Release("v1.3.0", "EdgeVoice-Setup-1.3.0.exe");
        pre["prerelease"] = true;
        Assert.Null(UpdateChecker.Newer(pre, new Version(1, 2, 0)));
    }

    [Fact]
    public void 사용자_설정이_기본값_위에_덮이고_값_하나만_바꿔_쓴다()
    {
        var dir = Directory.CreateTempSubdirectory().FullName;
        var basePath = Path.Combine(dir, "base.json");
        var userPath = Path.Combine(dir, "user", "appsettings.json");
        File.WriteAllText(basePath, """{"BackendUrl":"http://localhost:11000","AudioGatewayWsUrl":"ws://localhost:11008/ws/audio"}""");
        UserSettings.Set(userPath, "BackendUrl", "http://192.168.0.10:11000");
        UserSettings.Set(userPath, "CheckForUpdates", false);

        var options = UserSettings.Load(basePath, userPath);

        Assert.Equal("http://192.168.0.10:11000", options.BackendUrl);
        Assert.Equal("ws://localhost:11008/ws/audio", options.AudioGatewayWsUrl);
        Assert.False(options.CheckForUpdates);
        Assert.True(UserSettings.Load(basePath, Path.Combine(dir, "없음.json")).CheckForUpdates);
        Directory.Delete(dir, true);
    }

    [AvaloniaFact]
    public async Task 설정의_업데이트_자동_확인을_끄고_저장하면_사용자_설정_파일에_쓴다()
    {
        using var s = new Scenario();
        var settings = s.Main.Settings;
        var path = Path.Combine(Directory.CreateTempSubdirectory().FullName, "appsettings.json");
        settings.UserSettingsPath = path;
        await Scenario.WaitUntil(() => settings.ContextWindowSize == 10);
        Assert.True(settings.CheckForUpdates);
        Assert.False(settings.HasChanges);

        settings.CheckForUpdates = false;
        Assert.Contains("업데이트 자동 확인", settings.ChangeSummary);
        settings.SaveCommand.Execute();
        await Scenario.WaitUntil(() => !settings.HasChanges);

        Assert.False(UserSettings.Load(path, path).CheckForUpdates);
        Assert.Contains("업데이트 자동 확인", settings.SaveResult);
    }
}
