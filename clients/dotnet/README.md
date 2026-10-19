# EdgeVoice Agent (.NET / Avalonia)

기존 웹 대시보드(`services/backend/static/index.html`)를 .NET 8 Avalonia 트레이 상주 에이전트로 옮긴 클라이언트.
웹뷰 없이 모든 페이지를 Avalonia 네이티브 MVVM 화면(Prism.Core + Autofac)으로 다시 만들었다.

## 구성

| 프로젝트 | 내용 |
|---|---|
| `src/EdgeVoice.Agent.Core` (net8.0) | 백엔드 REST/SSE 클라이언트, Orchestrator 상태 모니터(`/api/status/stream`), 마이크 → audio-gateway(`/ws/audio`) 스트리머, Autofac 모듈 `EdgeVoiceCoreModule` |
| `src/EdgeVoice.Agent.Desktop` (net8.0, Avalonia 11) | 트레이 아이콘 + 파형 오버레이, 메인 창(Dashboard / Chat / Knowledge / Settings / History / Logs), Prism.Core MVVM + Autofac DI. Windows / Linux / macOS |
| `tests/EdgeVoice.Agent.Core.Tests` | Core 단위 테스트 (`dotnet test EdgeVoice.Agent.sln`) |
| `tests/EdgeVoice.Agent.Desktop.Tests` | [헤드리스] Avalonia.Headless + 가짜 백엔드(HttpListener) 시나리오 테스트: 테마·대시보드 차트·6개 페이지·채팅·설정·로그·트레이 파형, 라이트/다크 스크린샷(`bin/.../screenshots`) |
| `tests/EdgeVoice.Agent.Desktop.HeadedTests` | [헤디드] 실제 창 + 실행 중인 docker 백엔드 시나리오. 기본은 건너뜀, `dotnet test tests/EdgeVoice.Agent.Desktop.HeadedTests -e EDGEVOICE_HEADED=1` 로 실행 (`EDGEVOICE_BACKEND_URL` 로 주소 변경) |

## 디자인

- Microsoft 365(Office, Fluent 2) 형태: 파란 앱 바(`#0F6CBD`), 왼쪽 탐색 창, 회색 캔버스 위 카드. 색은 `App.axaml` 의 `Office*Brush` 테마 리소스(Light/Dark)에 모여 있다.
- 앱 바 오른쪽 버튼으로 라이트/다크 전환 (처음에는 OS 테마를 따름).
- 대시보드 차트(LiveCharts2): GPU 사용률 추이(최근 30회), 서비스 상태 도넛, 로그 레벨별/서비스별 건수.

> 마이크 입력(`MicrophoneStreamer`)은 NAudio(WinMM)를 쓰므로 현재 Windows 에서만 동작한다. Linux/Jetson 에서는 화면·채팅·트레이 상태 표시는 되지만 "말하기"는 연결 실패로 표시된다.

## 실행

```
cd clients/dotnet
dotnet run --project src/EdgeVoice.Agent.Desktop
```

접속 주소는 `src/EdgeVoice.Agent.Desktop/appsettings.json` (`BackendUrl`, `AudioGatewayWsUrl`, 기본값은 docker-compose.dev.yml 의 호스트 포트 11000 / 11008).
`%LOCALAPPDATA%\EdgeVoice\appsettings.json`(설치 마법사·설정 탭이 쓰는 사용자 설정, `CheckForUpdates` 포함)이 있으면 그 값이 위에 덮입니다(`UserSettings.cs`).

## 설치 프로그램·자동 업데이트

- `installer/EdgeVoice.iss` (Inno Setup 6): 특징 소개 페이지(`assets/installer/*.bmp`) → 연결 설정 → 사용자 단위 설치. 같은 폴더에 다시 설치하면 앱을 닫고 기존 파일을 지운 뒤 새로 깝니다.
- `UpdateChecker.cs`: 시작할 때 GitHub 최신 릴리스(`Repository` 상수, 기본 `ghlee0786/EdgeVoice`)가 지금 버전보다 새것이면 묻고, [확인] 이면 `EdgeVoice-Setup-*.exe` 를 받아 `/SILENT` 로 실행합니다. 개발 빌드(버전 0.0.0)는 확인하지 않습니다.
- 버전은 릴리스 태그에서 `-p:Version=` 으로 들어갑니다(`.github/workflows/release.yml`).
- 설치 프로그램 구성 요소 [AI 서버] 는 `deploy/`(배포용 compose · `setup-server.ps1` · `download-models.ps1`)와 서버가 마운트하는 파일을 AI 서버 폴더에 두고 `setup-server.ps1` 을 실행합니다.

## AI 서비스 끄기·켜기 (VRAM)

- `HostCompose.cs`: 백엔드 컨테이너의 compose 라벨로 프로젝트를 찾아 `stop llm stt tts embedding [vision]` / `up -d llm stt tts embedding` 명령을 만든다.
- `AiServices.cs`: 트레이 메뉴 'AI 서비스 끄기 (VRAM 비우기) / 켜기', 앱 시작 때 꺼져 있으면 켜고 health 가 모두 healthy 일 때까지 "AI 준비 중 (약 3분)".
- 설정 '앱을 종료할 때 AI 서비스도 끄기'(`StopAiServicesOnExit`, 기본 꺼짐)를 켜면 트레이 [종료] 때 함께 내린다. 백엔드가 원격이면 메뉴가 없다.

## 트레이 파형

웹을 열지 않고 트레이 아이콘과 화면 오른쪽 아래 오버레이만으로 음성 상태를 확인하고 말할 수 있다.

| 상태 | 표시 |
|---|---|
| 듣는 중 (사용자 음성 수신, `listening` 또는 로컬 마이크 스트리밍) | 파란 좁쌀 점들이 퍼짐, 마이크 레벨에 따라 점 크기·속도 변화 |
| 말하는 중 (TTS, `tts_processing`) | 초록 물결 원이 퍼짐 |
| 생각 중 (`stt_processing` / `llm_processing`) | 보라 점 3개 회전 |
| 대기 / 오류 | 회색 / 빨간 점 |

- 트레이 아이콘 왼쪽 클릭 또는 오버레이 왼쪽 클릭: 말하기(마이크 스트리밍) 시작/중지
- 오버레이 오른쪽 클릭 또는 트레이 메뉴 "EdgeVoice 창 열기": 메인 창
- 오버레이 드래그: 위치 이동, 트레이 메뉴에서 숨김/표시

## 다른 호스트 프로그램(예: Dotnet.Ironwall.Monitoring)에 붙이기

Core 는 UI 프레임워크에 의존하지 않는다. 호스트의 Autofac 컨테이너에 모듈을 등록하고 서비스를 주입받아 쓴다.

```csharp
builder.RegisterModule(new EdgeVoiceCoreModule(new EdgeVoiceOptions { BackendUrl = "http://edge:11000" }));
// EdgeVoiceApiClient.ChatAsync(...)   : 상황 설명을 보내 분석/조치 제안 받기
// VoiceStateMonitor.StateChanged      : 음성 상태 표시
// MicrophoneStreamer.StartAsync()/Stop(): 음성 입력
```
