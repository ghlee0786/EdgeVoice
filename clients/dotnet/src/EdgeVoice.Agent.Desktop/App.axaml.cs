using System;
using System.IO;
using Autofac;
using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using EdgeVoice.Agent.Core;
using EdgeVoice.Agent.Desktop.Tray;
using EdgeVoice.Agent.Desktop.ViewModels;

namespace EdgeVoice.Agent.Desktop;

/// <summary>
/// 트레이 상주형 EdgeVoice 에이전트(Avalonia). 시작 시 메인 창 없이 트레이 아이콘 + 파형 오버레이만 띄우고,
/// 메인 창(기존 웹 대시보드 기능)은 요청 시 생성한다.
/// </summary>
public partial class App : Application
{
    private IContainer? _container;
    private TrayController? _tray;

    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            // exe 옆 기본값 위에 사용자 설정(설치 마법사·설정 탭이 쓴 값)을 덮는다
            var options = UserSettings.Load(Path.Combine(AppContext.BaseDirectory, "appsettings.json"), UserSettings.DefaultPath);

            _container = BuildContainer(options);
            _container.Resolve<VoiceStateMonitor>().Start();
            _tray = new TrayController(
                this,
                _container.Resolve<VoiceStateMonitor>(),
                _container.Resolve<MicrophoneStreamer>(),
                _container.Resolve<AlwaysOnMicrophone>(),
                OpenMainWindow,
                () => desktop.Shutdown(),
                () => _container.Resolve<EdgeVoiceApiClient>()
                    .SendAsync(System.Net.Http.HttpMethod.Post, "api/orchestrator/stop", null),
                () => _container.Resolve<EdgeVoiceApiClient>()
                    .SendAsync(System.Net.Http.HttpMethod.Post, "api/orchestrator/listen", null));

            desktop.Exit += (_, _) =>
            {
                _tray?.Dispose();
                _container?.Dispose();
            };

            if (options.CheckForUpdates && !UpdateChecker.IsDevBuild)
            {
                CheckForUpdate(() => desktop.Shutdown());
            }
            AttachAiServices(options);
        }

        base.OnFrameworkInitializationCompleted();
    }

    /// <summary>
    /// 이 PC 의 docker 에 백엔드가 있으면 트레이에 'AI 서비스 끄기/켜기' 를 붙이고, 꺼져 있던 GPU 서비스를 켠다.
    /// [종료] 때 끌지는 설정의 '앱을 종료할 때 AI 서비스도 끄기' (기본 꺼짐).
    /// </summary>
    private async void AttachAiServices(EdgeVoiceOptions options)
    {
        if (await AiServices.FindAsync(new Uri(options.BackendUrl)) is not { } ai || _tray is null)
        {
            return;
        }

        _tray.AttachAi(ai);
        _tray.BeforeExit = async () =>
        {
            if (AiServices.ShouldStopOnExit(options, ai))
            {
                await ai.StopAsync();
            }
        };
        try
        {
            await ai.EnsureStartedAsync();
        }
        catch (Exception)
        {
            // docker 가 응답하지 않으면 켜지 않고 그대로 둔다 (메뉴로 다시 켤 수 있다)
        }
    }

    /// <summary>새 릴리스가 있으면 업데이트할지 묻고, [확인]이면 설치 프로그램을 받아 실행한 뒤 앱을 끝낸다.</summary>
    private static async void CheckForUpdate(Action exit)
    {
        using var http = UpdateChecker.CreateClient();
        if (await UpdateChecker.FindNewerAsync(http) is not { } release
            || !await Dialogs.ConfirmAsync("EdgeVoice 업데이트",
                $"새 버전 {release.Tag} 이(가) 나왔습니다 (지금 {UpdateChecker.Current}).\n" +
                "업데이트할까요? [확인]을 누르면 설치 프로그램을 받아 설치하고 앱을 다시 띄웁니다.\n" +
                "(설정 탭의 '업데이트 자동 확인' 을 끄면 묻지 않습니다)",
                "확인", "나중에", withoutOwner: true))
        {
            return;
        }

        try
        {
            await UpdateChecker.InstallAsync(http, release);
            exit();
        }
        catch (Exception ex)
        {
            await Dialogs.ConfirmAsync("EdgeVoice 업데이트", $"업데이트하지 못했습니다 — {ex.Message}", "확인", null, withoutOwner: true);
        }
    }

    /// <summary>메인 화면 DI 구성. 헤드리스 시나리오 테스트도 같은 구성을 쓴다.</summary>
    public static IContainer BuildContainer(EdgeVoiceOptions options)
    {
        var builder = new ContainerBuilder();
        builder.RegisterModule(new EdgeVoiceCoreModule(options));
        builder.RegisterType<DashboardViewModel>().SingleInstance();
        builder.RegisterType<ChatViewModel>().SingleInstance();
        builder.RegisterType<KnowledgeViewModel>().SingleInstance();
        builder.RegisterType<SettingsViewModel>().SingleInstance();
        builder.RegisterType<HistoryViewModel>().SingleInstance();
        builder.RegisterType<LogsViewModel>().SingleInstance();
        builder.RegisterType<MainViewModel>().SingleInstance();
        builder.RegisterType<MainWindow>().SingleInstance();
        return builder.Build();
    }

    private void OpenMainWindow()
    {
        var window = _container!.Resolve<MainWindow>();
        window.Show();
        window.Activate();
    }
}
