using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Layout;
using Avalonia.Platform.Storage;

namespace EdgeVoice.Agent.Desktop;

/// <summary>Avalonia 에는 MessageBox/OpenFileDialog 가 없어 메인 창 기준으로 직접 띄운다.</summary>
public static class Dialogs
{
    private static Window? Owner
        => (Application.Current?.ApplicationLifetime as IClassicDesktopStyleApplicationLifetime)?.Windows.OfType<MainWindow>().FirstOrDefault();

    /// <param name="noText">null 이면 버튼 하나(알림)만.</param>
    /// <param name="withoutOwner">메인 창이 없어도(트레이만 떠 있을 때) 화면 가운데에 띄운다 — 업데이트 확인용.</param>
    public static async Task<bool> ConfirmAsync(string title, string message, string yesText = "예", string? noText = "아니요",
        bool withoutOwner = false)
    {
        var owner = Owner;
        if (owner is null && !withoutOwner)
        {
            return false;
        }

        var dialog = new Window
        {
            Title = title,
            Width = 420,
            SizeToContent = SizeToContent.Height,
            CanResize = false,
            WindowStartupLocation = owner is null ? WindowStartupLocation.CenterScreen : WindowStartupLocation.CenterOwner,
        };
        var yes = new Button { Content = yesText, IsDefault = true, Margin = new Thickness(0, 0, 6, 0) };
        var no = new Button { Content = noText, IsCancel = true, IsVisible = noText is not null };
        var result = false;
        yes.Click += (_, _) => { result = true; dialog.Close(true); };
        no.Click += (_, _) => dialog.Close(false);
        dialog.Content = new StackPanel
        {
            Margin = new Thickness(16),
            Spacing = 12,
            Children =
            {
                new TextBlock { Text = message, TextWrapping = Avalonia.Media.TextWrapping.Wrap },
                new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Children = { yes, no } },
            },
        };
        if (owner is not null)
        {
            return await dialog.ShowDialog<bool>(owner);
        }

        var closed = new TaskCompletionSource();
        dialog.Closed += (_, _) => closed.TrySetResult();
        dialog.Show();
        await closed.Task;
        return result;
    }

    public static async Task<IReadOnlyList<string>> OpenFilesAsync()
    {
        if (Owner is not { } owner)
        {
            return [];
        }

        var files = await owner.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            AllowMultiple = true,
            FileTypeFilter =
            [
                new FilePickerFileType("문서") { Patterns = ["*.pdf", "*.txt", "*.md", "*.docx"] },
                FilePickerFileTypes.All,
            ],
        });
        return files.Select(f => f.TryGetLocalPath()).OfType<string>().ToList();
    }
}
