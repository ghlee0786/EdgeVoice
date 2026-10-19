namespace EdgeVoice.Agent.Core;

/// <summary>EdgeVoice 백엔드 접속 설정 (docker-compose.dev.yml 기본 호스트 포트 기준).</summary>
public sealed class EdgeVoiceOptions
{
    public string BackendUrl { get; set; } = "http://localhost:11000";

    public string AudioGatewayWsUrl { get; set; } = "ws://localhost:11008/ws/audio";

    /// <summary>시작할 때 GitHub Releases 에서 새 버전을 확인한다 (설정 탭·설치 마법사에서 켜고 끈다).</summary>
    public bool CheckForUpdates { get; set; } = true;

    /// <summary>트레이 [종료] 때 이 PC 의 GPU AI 서비스도 내려 VRAM 을 비운다 (기본 꺼짐 — 다시 켜면 LLM 준비에 약 3분).</summary>
    public bool StopAiServicesOnExit { get; set; }
}
