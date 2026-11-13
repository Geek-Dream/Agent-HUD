using AgentHUD.Link;
using AgentHUD.Windows.Services;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using QRCoder;

namespace AgentHUD.Windows;

public sealed partial class LinkSettingsDialog : ContentDialog
{
    private DispatcherQueueTimer? _timer;
    private DateTimeOffset _expiresAt;

    public LinkSettingsDialog()
    {
        InitializeComponent();
    }

    private async void LinkSettingsDialog_Loaded(object sender, RoutedEventArgs args)
    {
        if (!AgentHudLinkRuntime.IsRunning)
        {
            StatusText.Text = "正在启动局域网服务…";
            await AgentHudLinkRuntime.RestartAsync();
        }

        RefreshOffer();
        RefreshDevices();
        _timer = DispatcherQueue.CreateTimer();
        _timer.Interval = TimeSpan.FromSeconds(1);
        _timer.Tick += (_, _) => UpdateExpiryText();
        _timer.Start();
    }

    private void LinkSettingsDialog_Unloaded(object sender, RoutedEventArgs args)
    {
        _timer?.Stop();
    }

    private void NewPairingButton_Click(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        args.Cancel = true;
        RefreshOffer();
    }

    private async void RestartButton_Click(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        args.Cancel = true;
        StatusText.Text = "正在重启局域网服务…";
        await AgentHudLinkRuntime.RestartAsync();
        RefreshOffer();
        RefreshDevices();
    }

    private void RevokeDevice_Click(object sender, RoutedEventArgs args)
    {
        if (sender is Button { Tag: string deviceId })
        {
            AgentHudLinkRuntime.RevokeDevice(deviceId);
            RefreshDevices();
        }
    }

    private void ConversationToggle_Toggled(object sender, RoutedEventArgs args)
    {
        if (sender is ToggleSwitch { Tag: string deviceId, IsOn: var enabled })
        {
            AgentHudLinkRuntime.SetConversationEnabled(deviceId, enabled);
        }
    }

    private async void RefreshOffer()
    {
        try
        {
            var offer = AgentHudLinkRuntime.CreatePairingOffer();
            _expiresAt = offer.ExpiresAt;
            CodeText.Text = offer.Code;
            ServiceText.Text = AgentHudLinkRuntime.ServiceAddressText();
            StatusText.Text = string.Empty;
            UpdateExpiryText();

            using var generator = new QRCodeGenerator();
            using var data = generator.CreateQrCode(offer.Payload, QRCodeGenerator.ECCLevel.Q);
            using var qrCode = new PngByteQRCode(data);
            var bytes = qrCode.GetGraphic(9);
            using var memory = new MemoryStream(bytes);
            using var stream = memory.AsRandomAccessStream();
            var image = new BitmapImage();
            await image.SetSourceAsync(stream);
            QrImage.Source = image;
        }
        catch (Exception error)
        {
            QrImage.Source = null;
            CodeText.Text = "------";
            ExpiresText.Text = string.Empty;
            ServiceText.Text = AgentHudLinkRuntime.ServiceAddressText();
            StatusText.Text = error.Message;
        }
    }

    private void RefreshDevices()
    {
        DeviceList.ItemsSource = null;
        DeviceList.ItemsSource = AgentHudLinkRuntime.Devices;
    }

    private void UpdateExpiryText()
    {
        var remaining = _expiresAt - DateTimeOffset.Now;
        ExpiresText.Text = remaining > TimeSpan.Zero
            ? $"配对码将在 {Math.Max(1, (int)Math.Ceiling(remaining.TotalSeconds))} 秒后失效"
            : "配对码已失效，请生成新配对码";
    }
}
