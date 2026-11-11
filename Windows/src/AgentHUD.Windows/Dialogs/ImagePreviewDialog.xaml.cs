using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace AgentHUD.Windows;

public sealed partial class ImagePreviewDialog : ContentDialog
{
    private readonly IReadOnlyList<PromptImageViewModel> _images;
    private int _selectedIndex;
    private float _zoomFactor = 1;
    private CancellationTokenSource? _loadCancellation;

    public ImagePreviewDialog(
        IReadOnlyList<PromptImageViewModel> images,
        int initialIndex)
    {
        _images = images;
        _selectedIndex = Math.Clamp(initialIndex, 0, Math.Max(images.Count - 1, 0));
        InitializeComponent();
        UpdateNavigationVisibility();
    }

    private async void ImagePreviewDialog_Opened(
        ContentDialog sender,
        ContentDialogOpenedEventArgs args)
    {
        ImageScrollViewer.Focus(FocusState.Programmatic);
        await ShowCurrentImageAsync();
    }

    private void ImagePreviewDialog_Closed(
        ContentDialog sender,
        ContentDialogClosedEventArgs args)
    {
        _loadCancellation?.Cancel();
        _loadCancellation?.Dispose();
        _loadCancellation = null;
        PreviewImage.Source = null;
    }

    private void PreviousButton_Click(object sender, RoutedEventArgs e) => ShowPrevious();

    private void NextButton_Click(object sender, RoutedEventArgs e) => ShowNext();

    private void ZoomOutButton_Click(object sender, RoutedEventArgs e) =>
        ApplyZoom(_zoomFactor - 0.25f);

    private void ZoomInButton_Click(object sender, RoutedEventArgs e) =>
        ApplyZoom(_zoomFactor + 0.25f);

    private void ResetZoomButton_Click(object sender, RoutedEventArgs e) => ResetZoom();

    private void PreviewImage_DoubleTapped(
        object sender,
        DoubleTappedRoutedEventArgs e)
    {
        ResetZoom();
        e.Handled = true;
    }

    private async void ImagePreviewDialog_KeyDown(
        object sender,
        KeyRoutedEventArgs e)
    {
        switch (e.Key)
        {
            case VirtualKey.Left:
                ShowPrevious();
                e.Handled = true;
                break;
            case VirtualKey.Right:
                ShowNext();
                e.Handled = true;
                break;
            case VirtualKey.Add:
                ApplyZoom(_zoomFactor + 0.25f);
                e.Handled = true;
                break;
            case VirtualKey.Subtract:
                ApplyZoom(_zoomFactor - 0.25f);
                e.Handled = true;
                break;
            case VirtualKey.Number0:
                ResetZoom();
                e.Handled = true;
                break;
        }
    }

    private void ShowPrevious()
    {
        if (_images.Count < 2)
        {
            return;
        }
        _selectedIndex = _selectedIndex == 0 ? _images.Count - 1 : _selectedIndex - 1;
        _ = ShowCurrentImageAsync();
    }

    private void ShowNext()
    {
        if (_images.Count < 2)
        {
            return;
        }
        _selectedIndex = _selectedIndex == _images.Count - 1 ? 0 : _selectedIndex + 1;
        _ = ShowCurrentImageAsync();
    }

    private async Task ShowCurrentImageAsync()
    {
        _loadCancellation?.Cancel();
        _loadCancellation?.Dispose();
        _loadCancellation = new CancellationTokenSource();
        var cancellationToken = _loadCancellation.Token;

        CounterText.Text = _images.Count == 0
            ? "[图片]"
            : $"[图片{_selectedIndex + 1} / {_images.Count}]";
        UpdateNavigationVisibility();
        ResetZoom();

        if (_images.Count == 0)
        {
            ShowUnavailable();
            return;
        }

        var image = _images[_selectedIndex];
        if (image.ImageSource is null)
        {
            await image.LoadAsync();
        }
        if (cancellationToken.IsCancellationRequested)
        {
            return;
        }

        PreviewImage.Source = image.ImageSource;
        PreviewImage.Visibility = image.ImageSource is null
            ? Visibility.Collapsed
            : Visibility.Visible;
        UnavailablePanel.Visibility = image.ImageSource is null
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void ShowUnavailable()
    {
        PreviewImage.Source = null;
        PreviewImage.Visibility = Visibility.Collapsed;
        UnavailablePanel.Visibility = Visibility.Visible;
    }

    private void UpdateNavigationVisibility()
    {
        var visibility = _images.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
        PreviousButton.Visibility = visibility;
        NextButton.Visibility = visibility;
    }

    private void ApplyZoom(float value)
    {
        _zoomFactor = Math.Clamp(value, 0.5f, 4f);
        ImageScrollViewer.ChangeView(null, null, _zoomFactor, false);
        ZoomText.Text = $"{Math.Round(_zoomFactor * 100)}%";
    }

    private void ResetZoom()
    {
        _zoomFactor = 1;
        ImageScrollViewer.ChangeView(null, null, 1f, true);
        ZoomText.Text = "100%";
    }
}
