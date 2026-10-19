using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.VisualTree;
using EdgeVoice.Agent.Core;
using EdgeVoice.Agent.Desktop.Tray;
using Xunit;

namespace EdgeVoice.Agent.Desktop.Tests;

/// <summary>
/// README·설치 마법사용 화면 스크린샷. 개인 데이터가 보이지 않게 지어낸 가짜 백엔드 데이터로만 찍는다.
/// EDGEVOICE_SCREENSHOT_DIR 가 있을 때만 찍는다 (평소 dotnet test 에서는 아무것도 하지 않고 통과).
///   EDGEVOICE_SCREENSHOT_DIR=assets/screenshots dotnet test --filter ReadmeScreenshotTests
/// </summary>
public class ReadmeScreenshotTests
{
    private static readonly string? ShotDir = Environment.GetEnvironmentVariable("EDGEVOICE_SCREENSHOT_DIR");

    private static string Dir => Directory.CreateDirectory(ShotDir!).FullName;

    private static void Sample(FakeBackend b)
    {
        b.Json["/api/dashboard/init"] = """
            {"services":{"orchestrator":{"status":"healthy","state":"IDLE"},"stt":{"status":"healthy"},"tts":{"status":"healthy"},
                         "llm":{"status":"healthy"},"rag":{"status":"healthy"},"wake_word":{"status":"healthy"},
                         "audio_gateway":{"status":"healthy"},"embedding":{"status":"healthy"}},
             "system":{"gpu":{"available":true,"used_gb":11.2,"total_gb":24,"utilization_percent":37},
                       "sessions":{"active":1},"documents":{"count":3}}}
            """;
        b.Json["/api/logs/stats"] = """{"total":186,"by_level":{"INFO":151,"WARNING":27,"ERROR":2,"DEBUG":6},"by_service":{"orchestrator":58,"stt":41,"llm":44,"tts":29,"rag":14}}""";
        b.Json["/api/logs"] = """
            {"logs":[
             {"created_at":"2026-10-19T09:12:08","level":"INFO","service":"tts","stage":"synthesize","message":"답변 음성 2.4초 합성","duration_ms":310},
             {"created_at":"2026-10-19T09:12:07","level":"INFO","service":"llm","stage":"generate","message":"도구 youtube_play 호출 → 재생 시작","duration_ms":1840},
             {"created_at":"2026-10-19T09:12:05","level":"INFO","service":"stt","stage":"transcribe","message":"\"유튜브에서 잔잔한 피아노 음악 틀어 줘\"","duration_ms":420},
             {"created_at":"2026-10-19T09:12:03","level":"INFO","service":"orchestrator","stage":"wake_word","message":"호출어 감지 (hey_jarvis 0.82)","duration_ms":null},
             {"created_at":"2026-10-19T09:10:41","level":"WARNING","service":"rag","stage":"search","message":"관련 조각 없음 — 일반 답변으로","duration_ms":95},
             {"created_at":"2026-10-19T09:10:40","level":"INFO","service":"rag","stage":"embed","message":"질문 임베딩 1024차원","duration_ms":38}]}
            """;
        b.Json["/api/history"] = """
            {"messages":[
             {"id":"h6","session_id":"s1","role":"assistant","content":"잔잔한 피아노 음악을 유튜브에서 틀었어요. 광고는 건너뛰었습니다.","timestamp":"2026-10-19T09:12:08","source":"voice"},
             {"id":"h5","session_id":"s1","role":"user","content":"유튜브에서 잔잔한 피아노 음악 틀어 줘","timestamp":"2026-10-19T09:12:05","source":"voice"},
             {"id":"h4","session_id":"s1","role":"assistant","content":"설명서에 따르면 필터는 3개월마다 바꾸면 됩니다.","timestamp":"2026-10-19T09:10:44","source":"web"},
             {"id":"h3","session_id":"s1","role":"user","content":"공기청정기 필터 교체 주기 알려 줘","timestamp":"2026-10-19T09:10:40","source":"web"},
             {"id":"h2","session_id":"s1","role":"assistant","content":"지금은 오전 9시 8분입니다.","timestamp":"2026-10-19T09:08:02","source":"voice"},
             {"id":"h1","session_id":"s1","role":"user","content":"지금 몇 시야?","timestamp":"2026-10-19T09:08:00","source":"voice"}],"total":6}
            """;
        b.Json["/api/knowledge/documents"] = """
            {"documents":[{"id":"d1","filename":"공기청정기_사용설명서.pdf","chunk_count":42,"uploaded_at":"2026-10-18T14:02:11"},
                          {"id":"d2","filename":"사내_휴가_규정(예시).docx","chunk_count":18,"uploaded_at":"2026-10-18T14:03:40"},
                          {"id":"d3","filename":"제품_FAQ.md","chunk_count":9,"uploaded_at":"2026-10-19T08:55:02"}]}
            """;
        b.Json["/api/settings/options"] = """
            {"tts_engines":[{"id":"melo","display_name":"MeloTTS Korean","recommended_for":"한국어"},{"id":"edge","display_name":"Edge TTS","recommended_for":"다국어"}],
             "tts_voices":{"melo":["KR"],"edge":["ko-KR-SunHiNeural","ko-KR-InJoonNeural"]},
             "stt_models":[{"id":"medium","display_name":"Whisper Medium","vram_gb":5,"korean_quality":"좋음"}],
             "llm_models":[{"id":"qwen2.5-7b-instruct-awq","display_name":"Qwen 2.5 7B AWQ","vram_gb":5}],
             "current":{"tts_engine":"melo","tts_voice":"KR","stt_model":"medium","llm_model":"qwen2.5-7b-instruct-awq","wake_word_threshold":0.5},
             "saved":{"tts_engine":"melo","tts_voice":"KR","stt_model":"medium","llm_model":"qwen2.5-7b-instruct-awq","wake_word_threshold":0.5},
             "pending_restart":[]}
            """;
        b.Json["/api/settings/general"] = """{"wake_word":"hey_jarvis","language":"ko","voice_speed":1.1,"wake_word_threshold":0.5,"end_pause_seconds":1.5,"listening_timeout_seconds":10}""";
        b.Json["/api/settings/llm/context"] = """{"context_enabled":true,"context_window_size":20}""";
        b.Json["/api/settings/tools"] = """
            {"internet_enabled":true,"search_provider":"searxng","timezone":"Asia/Seoul","locale":"ko-KR","location":"서울",
             "weather_enabled":true,"follow_pc_timezone":false,
             "tools":["get_time","get_weather","web_search","youtube_play","close_browser","open_paint"],"server_time":"2026년 10월 19일 (월요일) 09시 12분 KST"}
            """;
        b.Json["/api/settings/mcp"] = """
            {"servers":[{"name":"browser","url":"http://host.docker.internal:8931/mcp","command":null,"args":[],"env":null,
              "allowed_tools":["browser_navigate","browser_click","browser_snapshot"],"trusted":true,"always_confirm":[],"no_confirm":[],
              "timeout":60,"enabled":true,"status":"connected","error":"","tools":["browser_navigate","browser_click","browser_snapshot"]}]}
            """;
        b.Json["/api/settings/skills"] = """
            {"builtin":[{"name":"get_time","description":"지금 시각 알려 주기","enabled":true,"active":true},
                        {"name":"youtube_play","description":"유튜브 검색·재생 (광고 자동 건너뛰기)","enabled":true,"active":true},
                        {"name":"open_paint","description":"그림판 열고 그리기","enabled":true,"active":true}],
             "disabled_tools":[],
             "prompts":[{"name":"존댓말","description":"항상 존댓말","instructions":"항상 존댓말로 답한다.","enabled":true}]}
            """;
        b.Json["/api/sessions/active"] = """{"session_id":"s1"}""";
        b.Sse["/api/chat/stream"] = new[]
        {
            ("init", """
                {"session_id":"s1","messages":[
                 {"id":"c1","session_id":"s1","role":"user","content":"지금 몇 시야?","source":"voice"},
                 {"id":"c2","session_id":"s1","role":"assistant","content":"지금은 오전 9시 8분입니다.","source":"voice"},
                 {"id":"c3","session_id":"s1","role":"user","content":"공기청정기 필터 교체 주기 알려 줘","source":"web"},
                 {"id":"c4","session_id":"s1","role":"assistant","content":"설명서에 따르면 필터는 3개월마다 바꾸면 됩니다.","source":"web",
                  "sources":[{"filename":"공기청정기_사용설명서.pdf"}]},
                 {"id":"c5","session_id":"s1","role":"user","content":"유튜브에서 잔잔한 피아노 음악 틀어 줘","source":"voice"},
                 {"id":"c6","session_id":"s1","role":"assistant","content":"잔잔한 피아노 음악을 유튜브에서 틀었어요. 광고는 건너뛰었습니다.","source":"voice"}]}
                """.ReplaceLineEndings(" ")),
        };
    }

    private static async Task Shoot(Window w, string name)
    {
        await Scenario.Settle(300);
        w.CaptureRenderedFrame()!.Save(Path.Combine(Dir, name + ".png"));
    }

    [AvaloniaFact]
    public async Task 각_탭과_설정_카드를_찍는다()
    {
        if (string.IsNullOrEmpty(ShotDir))
        {
            return;
        }

        using var s = new Scenario(setup: Sample);
        var w = s.Show();
        await Scenario.WaitUntil(() => s.Main.Settings.McpServers.Count == 1 && s.Main.Chat.Messages.Count == 6
                                       && s.Main.Knowledge.Documents.Count == 3 && s.Main.History.Items.Count > 0
                                       && s.Main.Logs.Logs.Count == 6);
        var nav = w.FindControl<TabControl>("Nav")!;
        foreach (var (header, name) in new[]
                 {
                     ("Dashboard", "dashboard"), ("Chat", "chat"), ("Knowledge", "knowledge"),
                     ("History", "history"), ("Logs", "logs"), ("Settings", "settings"),
                 })
        {
            nav.SelectedItem = nav.Items.Cast<TabItem>().Single(t => (string)t.Header! == header);
            await Shoot(w, name);
        }

        // 설정은 길어서 스크롤해 가며 카드를 나눠 찍는다
        var scroll = ((Control)nav.SelectedContent!).GetVisualDescendants().OfType<ScrollViewer>().First();
        var update = w.FindControl<CheckBox>("CheckForUpdates")!;
        scroll.Offset = new Vector(0, update.TranslatePoint(default, scroll)!.Value.Y - 360);
        await Shoot(w, "settings-update");
        scroll.Offset = new Vector(0, scroll.Extent.Height);
        await Shoot(w, "settings-more");

        s.Main.IsDarkTheme = true;
        nav.SelectedItem = nav.Items.Cast<TabItem>().Single(t => (string)t.Header! == "Chat");
        await Shoot(w, "chat-dark");
    }

    /// <summary>파형 창: 대기 → 듣기 → 생각(STT·LLM) → 말하기 순서의 프레임 (GIF 는 스크립트가 묶는다).</summary>
    [AvaloniaFact]
    public async Task 파형_창_프레임을_찍는다()
    {
        if (string.IsNullOrEmpty(ShotDir))
        {
            return;
        }

        var dir = Directory.CreateDirectory(Path.Combine(Dir, "orb-frames")).FullName;
        var orb = new VoiceOrbWindow();
        orb.Show();
        var steps = new (VoiceState State, PipelineStage Stage, int Frames)[]
        {
            (VoiceState.Idle, PipelineStage.None, 8),
            (VoiceState.Listening, PipelineStage.Listen, 24),
            (VoiceState.Thinking, PipelineStage.Stt, 10),
            (VoiceState.Thinking, PipelineStage.Llm, 14),
            (VoiceState.Speaking, PipelineStage.Tts, 24),
        };
        var n = 0;
        foreach (var (state, stage, frames) in steps)
        {
            orb.SetStage(stage);
            for (var i = 0; i < frames; i++, n++)
            {
                // 트레이와 같은 위상 속도(프레임마다 1/24 바퀴), 듣기는 말소리처럼 들쭉날쭉한 레벨
                var level = state == VoiceState.Listening ? (float)(0.3 + 0.3 * Math.Abs(Math.Sin(i * 0.9))) : 0f;
                orb.Update(state, i / 24.0 % 1.0, level, "");
                await Scenario.Settle(30);
                orb.CaptureRenderedFrame()!.Save(Path.Combine(dir, $"{n:000}.png"));
            }
        }

        orb.Close();
    }
}
