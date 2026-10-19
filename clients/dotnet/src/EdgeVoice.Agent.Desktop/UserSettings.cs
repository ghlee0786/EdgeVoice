using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using EdgeVoice.Agent.Core;

namespace EdgeVoice.Agent.Desktop;

/// <summary>
/// 사용자 설정 파일(%LOCALAPPDATA%\EdgeVoice\appsettings.json). 설치 마법사가 쓰고, 설정 탭이 고친다.
/// 설치 폴더 밖에 있어 업데이트가 설치 폴더를 지워도 남는다. exe 옆 appsettings.json(기본값) 위에 덮어 읽는다.
/// </summary>
public static class UserSettings
{
    public static string DefaultPath { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "EdgeVoice", "appsettings.json");

    public static EdgeVoiceOptions Load(string basePath, string userPath)
    {
        var merged = Read(basePath);
        foreach (var (key, value) in Read(userPath))
        {
            merged[key] = value?.DeepClone();
        }

        return merged.Deserialize<EdgeVoiceOptions>() ?? new EdgeVoiceOptions();
    }

    /// <summary>값 하나만 바꿔 쓴다 (설치 마법사가 넣은 다른 값은 그대로).</summary>
    public static void Set(string path, string key, JsonNode? value)
    {
        var json = Read(path);
        json[key] = value;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, json.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    private static JsonObject Read(string path)
    {
        try
        {
            return File.Exists(path) ? JsonNode.Parse(File.ReadAllText(path)) as JsonObject ?? new JsonObject() : new JsonObject();
        }
        catch (JsonException)
        {
            // 손으로 고치다 깨진 파일은 기본값으로 시작한다
            return new JsonObject();
        }
    }
}
