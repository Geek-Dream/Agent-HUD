using AgentHUD.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AgentHUD.Windows;

public sealed partial class AISettingsDialog : ContentDialog
{
    private readonly MainViewModel _viewModel;

    public AISettingsDialog(MainViewModel viewModel)
    {
        _viewModel = viewModel;
        InitializeComponent();

        var configuration = _viewModel.AIConfiguration;
        EnabledSwitch.IsOn = configuration.Enabled;
        EndpointBox.Text = configuration.Endpoint;
        ModelBox.Text = configuration.Model;
        var savedSize = _viewModel.SavedExpandedWindowSize;
        ExpandedWidthBox.Value = savedSize.Width ?? ExpandedPanelSize.DefaultWidth;
        ExpandedHeightBox.Value = savedSize.Height ?? ExpandedPanelSize.DefaultHeight;
        UpdateKeyState();
    }

    private void AISettingsDialog_Opened(
        ContentDialog sender,
        ContentDialogOpenedEventArgs args)
    {
        EndpointBox.Focus(FocusState.Programmatic);
    }

    private async void AISettingsDialog_PrimaryButtonClick(
        ContentDialog sender,
        ContentDialogButtonClickEventArgs args)
    {
        _viewModel.SaveExpandedWindowSize(
            ExpandedWidthBox.Value,
            ExpandedHeightBox.Value);
        if (!TryReadConfiguration(
                forceEnabled: false,
                out var configuration,
                out var validationMessage))
        {
            args.Cancel = true;
            SetStatus(validationMessage, InfoBarSeverity.Error);
            return;
        }

        var deferral = args.GetDeferral();
        try
        {
            var draftKey = ApiKeyBox.Password.Trim();
            _viewModel.SaveAIConfiguration(
                configuration,
                draftKey.Length > 0 ? draftKey : null);
            ApiKeyBox.Password = string.Empty;
            UpdateKeyState();
            SetStatus("配置已保存。", InfoBarSeverity.Success);
            await Task.Delay(180);
        }
        catch (Exception error)
        {
            args.Cancel = true;
            SetStatus(error.Message, InfoBarSeverity.Error);
        }
        finally
        {
            deferral.Complete();
        }
    }

    private async void AISettingsDialog_SecondaryButtonClick(
        ContentDialog sender,
        ContentDialogButtonClickEventArgs args)
    {
        args.Cancel = true;
        if (!TryReadConfiguration(
                forceEnabled: true,
                out var configuration,
                out var validationMessage))
        {
            SetStatus(validationMessage, InfoBarSeverity.Error);
            return;
        }

        var apiKey = ApiKeyBox.Password.Trim();
        if (apiKey.Length == 0)
        {
            apiKey = _viewModel.GetSavedApiKey() ?? string.Empty;
        }
        if (apiKey.Length == 0)
        {
            SetStatus("请先填写 API Key。", InfoBarSeverity.Error);
            return;
        }

        var deferral = args.GetDeferral();
        try
        {
            SetStatus("正在测试连接…", InfoBarSeverity.Informational, showSpinner: true);
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(32));
            await _viewModel.TestAIConnectionAsync(
                configuration,
                apiKey,
                timeout.Token);
            SetStatus("连接成功，AI 可以生成标题。", InfoBarSeverity.Success);
        }
        catch (OperationCanceledException)
        {
            SetStatus("连接测试超时，请检查地址和网络。", InfoBarSeverity.Error);
        }
        catch (Exception error)
        {
            SetStatus($"连接失败：{error.Message}", InfoBarSeverity.Error);
        }
        finally
        {
            deferral.Complete();
        }
    }

    private void DeleteKeyButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            _viewModel.ClearApiKey();
            ApiKeyBox.Password = string.Empty;
            EnabledSwitch.IsOn = false;
            UpdateKeyState();
            SetStatus("API Key 已删除，AI 标题已关闭。", InfoBarSeverity.Success);
        }
        catch (Exception error)
        {
            SetStatus($"删除失败：{error.Message}", InfoBarSeverity.Error);
        }
    }

    private bool TryReadConfiguration(
        bool forceEnabled,
        out AIConfiguration configuration,
        out string validationMessage)
    {
        var endpoint = EndpointBox.Text.Trim();
        var model = ModelBox.Text.Trim();
        if (model.Length == 0)
        {
            configuration = new AIConfiguration();
            validationMessage = "请填写模型名称。";
            return false;
        }

        configuration = new AIConfiguration
        {
            Enabled = forceEnabled || EnabledSwitch.IsOn,
            Endpoint = endpoint,
            Model = model
        };
        if (configuration.ChatCompletionsUri is null)
        {
            validationMessage = "API 地址无效，请填写完整的 http 或 https 地址。";
            return false;
        }

        validationMessage = string.Empty;
        return true;
    }

    private void UpdateKeyState()
    {
        var hasKey = _viewModel.HasApiKey;
        ApiKeyBox.PlaceholderText = hasKey
            ? "已保存，留空保持不变"
            : "填写 API Key";
        ApiKeyHintText.Text = hasKey
            ? "密钥已保存在 Windows 凭据管理器"
            : "尚未配置密钥";
        DeleteKeyButton.IsEnabled = hasKey;
    }

    private void SetStatus(
        string message,
        InfoBarSeverity severity,
        bool showSpinner = false)
    {
        StatusBar.Message = message;
        StatusBar.Severity = severity;
        StatusBar.IsOpen = true;
        StatusBar.IsClosable = false;
        StatusBar.IsIconVisible = showSpinner || severity != InfoBarSeverity.Informational;
    }
}
