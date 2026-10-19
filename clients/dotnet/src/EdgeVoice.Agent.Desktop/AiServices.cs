using System;
using System.Linq;
using System.Threading.Tasks;
using EdgeVoice.Agent.Core;

namespace EdgeVoice.Agent.Desktop;

/// <summary>
/// 이 PC 의 GPU AI 서비스(llm·stt·tts·embedding) 끄기·켜기 — 앱을 꺼도 docker 의 서비스는 VRAM 을 잡고 있으므로
/// 사용자가 고를 때만 내린다(사용자 요청 2026-10-19: 선택식). 켤 때는 준비(health)될 때까지 안내를 보인다.
/// </summary>
public sealed class AiServices
{
    private readonly ComposeProject _project;
    private bool _busy;

    private AiServices(ComposeProject project) => _project = project;

    /// <summary>LLM 이 다시 준비되는 데 걸리는 대략의 시간 (지난 재시작 2분 51초).</summary>
    public const string ReadyNotice = "AI 준비 중 (약 3분)";

    /// <summary>마지막으로 본 상태: 켜짐 true · 꺼짐 false · 모름 null.</summary>
    public bool? Running { get; private set; }

    /// <summary>파형 창·트레이에 보일 안내 (끄는 중·준비 중). 평소에는 null.</summary>
    public string? Notice { get; private set; }

    public bool IsBusy => _busy;

    public event Action? Changed;

    /// <summary>백엔드가 이 PC 의 docker 에 있을 때만 (원격 백엔드면 null — 메뉴를 숨긴다).</summary>
    public static async Task<AiServices?> FindAsync(Uri backend)
        => await HostCompose.FindAsync(backend) is { } project ? new AiServices(project) : null;

    /// <summary>[종료] 때 AI 서비스도 끌지: 옵션을 켰고 이 PC 의 서비스를 찾았을 때만.</summary>
    public static bool ShouldStopOnExit(EdgeVoiceOptions options, AiServices? ai) => options.StopAiServicesOnExit && ai is not null;

    /// <summary>앱을 켤 때: GPU 서비스가 꺼져 있으면 켜고 준비될 때까지 기다린다.</summary>
    public async Task EnsureStartedAsync()
    {
        var running = await HostCompose.RunningAsync(_project);
        if (HostCompose.GpuServicesToStart.All(running.Contains))
        {
            Set(true, null);
            return;
        }

        await StartAsync();
    }

    /// <returns>끝났으면 null, 못 했으면 이유.</returns>
    public async Task<string?> StopAsync()
    {
        if (_busy)
        {
            return "이미 처리하는 중입니다";
        }

        _busy = true;
        Set(Running, "AI 서비스 끄는 중");
        var error = await HostCompose.StopGpuAsync(_project);
        _busy = false;
        Set(error is null ? false : Running, null);
        return error;
    }

    public async Task<string?> StartAsync()
    {
        if (_busy)
        {
            return "이미 처리하는 중입니다";
        }

        _busy = true;
        Set(Running, ReadyNotice);
        var error = await HostCompose.StartGpuAsync(_project);
        if (error is null)
        {
            // health 가 모두 healthy 가 될 때까지 (LLM 은 모델을 올리느라 몇 분 걸린다, 최대 10분)
            var until = DateTime.UtcNow.AddMinutes(10);
            while (!await HostCompose.GpuHealthyAsync(_project) && DateTime.UtcNow < until)
            {
                await Task.Delay(TimeSpan.FromSeconds(5));
            }
        }

        _busy = false;
        Set(error is null ? true : Running, null);
        return error;
    }

    private void Set(bool? running, string? notice)
    {
        Running = running;
        Notice = notice;
        Changed?.Invoke();
    }
}
