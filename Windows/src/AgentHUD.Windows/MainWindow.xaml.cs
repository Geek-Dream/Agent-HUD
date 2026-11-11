using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using AgentHUD.Core;
using Microsoft.UI;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.Graphics;
using Windows.UI.ViewManagement;
using WinRT.Interop;
using AgentHUD.Windows.Services;

namespace AgentHUD.Windows;

public sealed partial class MainWindow : Window
{
    private const int WmNcLButtonDown = 0x00A1;
    private const int HtCaption = 0x0002;
    private const int ExpandedWidth = 424;
    private const int ExpandedHeight = 620;
    private const int CollapsedWidth = 320;
    private const int CollapsedHeight = 62;

    private readonly MainViewModel _viewModel;
    private readonly AppWindow _appWindow;
    private readonly IntPtr _windowHandle;
    private readonly TrayIcon _trayIcon;
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer _positionSaveTimer;
    private CancellationTokenSource? _resizeAnimation;
    private CancellationTokenSource? _contentTransition;
    private bool _allowClose;
    private bool _isAnimatingWindow;
    private bool _usesSystemBackdrop;

    public MainWindow()
    {
        InitializeComponent();
        Title = "AgentHUD";
        _viewModel = new MainViewModel();
        RootGrid.DataContext = _viewModel;

        _windowHandle = WindowNative.GetWindowHandle(this);
        var windowId = Win32Interop.GetWindowIdFromWindow(_windowHandle);
        _appWindow = AppWindow.GetFromWindowId(windowId);
        ConfigureWindow();
        RestoreWindowPosition();

        _positionSaveTimer = DispatcherQueue.CreateTimer();
        _positionSaveTimer.Interval = TimeSpan.FromMilliseconds(350);
        _positionSaveTimer.IsRepeating = false;
        _positionSaveTimer.Tick += (_, _) => SaveWindowPosition();

        _trayIcon = new TrayIcon(
            _windowHandle,
            ToggleVisibility,
            ToggleExpanded,
            RefreshFromTray,
            TogglePrivacy,
            TogglePositionLock,
            OpenSettingsFromTray,
            ExitApplication,
            () => IsWindowVisible(_windowHandle),
            () => _viewModel.IsExpanded,
            () => _viewModel.PrivacyMode,
            () => _viewModel.PositionLocked);

        _viewModel.PropertyChanged += ViewModel_PropertyChanged;
        _viewModel.ExpansionStateChanged += ViewModel_ExpansionStateChanged;
        _viewModel.CompletionTransition += ViewModel_CompletionTransition;
        _appWindow.Changed += AppWindow_Changed;
        _appWindow.Closing += AppWindow_Closing;
        Closed += MainWindow_Closed;

        UpdateFilterVisuals();
        _viewModel.Start();
    }

    public MainViewModel ViewModel => _viewModel;

    private void ConfigureWindow()
    {
        if (_appWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsAlwaysOnTop = true;
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
            try
            {
                presenter.SetBorderAndTitleBar(false, false);
            }
            catch
            {
            }
        }

        _appWindow.TitleBar.ExtendsContentIntoTitleBar = true;
        _appWindow.TitleBar.ButtonBackgroundColor = Colors.Transparent;
        _appWindow.TitleBar.ButtonInactiveBackgroundColor = Colors.Transparent;
        _appWindow.TitleBar.ButtonForegroundColor = Colors.Transparent;
        _appWindow.TitleBar.ButtonInactiveForegroundColor = Colors.Transparent;

        try
        {
            if (MicaController.IsSupported())
            {
                SystemBackdrop = new MicaBackdrop { Kind = MicaKind.BaseAlt };
                _usesSystemBackdrop = true;
            }
            else if (DesktopAcrylicController.IsSupported())
            {
                SystemBackdrop = new DesktopAcrylicBackdrop();
                _usesSystemBackdrop = true;
            }
        }
        catch
        {
            _usesSystemBackdrop = false;
        }
        ApplyWindowBackground();
    }

    private void RestoreWindowPosition()
    {
        var expanded = _viewModel.IsExpanded;
        var width = expanded ? ExpandedWidth : CollapsedWidth;
        var height = expanded ? ExpandedHeight : CollapsedHeight;
        var workArea = WorkArea();
        var saved = _viewModel.SavedWindowPosition;
        var x = saved.X ?? (workArea.X + workArea.Width - width - 18);
        var y = saved.Y ?? (workArea.Y + 18);
        x = Math.Clamp(x, workArea.X, Math.Max(workArea.X, workArea.X + workArea.Width - width));
        y = Math.Clamp(y, workArea.Y, Math.Max(workArea.Y, workArea.Y + workArea.Height - height));
        _appWindow.MoveAndResize(new RectInt32(x, y, width, height));
    }

    private RectInt32 WorkArea()
    {
        var display = DisplayArea.GetFromWindowId(_appWindow.Id, DisplayAreaFallback.Primary);
        return display.WorkArea;
    }

    private async void ViewModel_ExpansionStateChanged(object? sender, EventArgs e)
    {
        UpdateFilterVisuals();
        _contentTransition?.Cancel();
        _contentTransition?.Dispose();
        _contentTransition = new CancellationTokenSource();
        var cancellationToken = _contentTransition.Token;

        var expanded = _viewModel.IsExpanded;
        var panel = expanded ? ExpandedPanel : CollapsedPanel;
        panel.Opacity = 0;
        var resizeTask = AnimateWindowSizeAsync(expanded);
        await Task.WhenAll(
            resizeTask,
            AnimateElementAsync(
                panel,
                entering: true,
                fromX: expanded ? 3 : 2,
                durationMs: expanded ? 240 : 210));
        if (cancellationToken.IsCancellationRequested)
        {
            return;
        }
    }

    private async Task AnimateWindowSizeAsync(bool expanded)
    {
        _resizeAnimation?.Cancel();
        _resizeAnimation?.Dispose();
        _resizeAnimation = new CancellationTokenSource();
        var cancellationToken = _resizeAnimation.Token;

        var startPosition = _appWindow.Position;
        var startSize = _appWindow.Size;
        var targetWidth = expanded ? ExpandedWidth : CollapsedWidth;
        var targetHeight = expanded ? ExpandedHeight : CollapsedHeight;
        var workArea = WorkArea();
        var targetX = Math.Clamp(
            startPosition.X + startSize.Width - targetWidth,
            workArea.X,
            Math.Max(workArea.X, workArea.X + workArea.Width - targetWidth));
        var targetY = Math.Clamp(
            startPosition.Y,
            workArea.Y,
            Math.Max(workArea.Y, workArea.Y + workArea.Height - targetHeight));

        _isAnimatingWindow = true;
        var timer = DispatcherQueue.CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(16);
        timer.IsRepeating = true;
        var completion = new TaskCompletionSource<bool>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var stopwatch = Stopwatch.StartNew();

        void Finish()
        {
            timer.Stop();
            timer.Tick -= OnTick;
        }

        void OnTick(Microsoft.UI.Dispatching.DispatcherQueueTimer sender, object args)
        {
            if (cancellationToken.IsCancellationRequested)
            {
                Finish();
                completion.TrySetCanceled(cancellationToken);
                return;
            }

            var progress = Math.Clamp(
                stopwatch.ElapsedMilliseconds / 310d,
                0,
                1);
            var eased = 1 - Math.Pow(1 - progress, 4);
            var width = Interpolate(startSize.Width, targetWidth, eased);
            var height = Interpolate(startSize.Height, targetHeight, eased);
            var x = Interpolate(startPosition.X, targetX, eased);
            var y = Interpolate(startPosition.Y, targetY, eased);
            _appWindow.MoveAndResize(new RectInt32(
                (int)Math.Round(x),
                (int)Math.Round(y),
                Math.Max(1, (int)Math.Round(width)),
                Math.Max(1, (int)Math.Round(height))));

            if (progress < 1)
            {
                return;
            }

            _appWindow.MoveAndResize(new RectInt32(
                targetX,
                targetY,
                targetWidth,
                targetHeight));
            Finish();
            completion.TrySetResult(true);
        }

        timer.Tick += OnTick;
        using var cancellationRegistration = cancellationToken.Register(() =>
            DispatcherQueue.TryEnqueue(() =>
            {
                Finish();
                completion.TrySetCanceled(cancellationToken);
            }));
        timer.Start();
        try
        {
            await completion.Task;
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            Finish();
            _isAnimatingWindow = false;
            SaveWindowPositionSoon();
        }
    }

    private static double Interpolate(double start, double target, double progress) =>
        start + (target - start) * progress;

    private async Task AnimateElementAsync(
        FrameworkElement element,
        bool entering,
        double fromX = 9,
        int durationMs = 170)
    {
        if (element.RenderTransform is not CompositeTransform transform)
        {
            transform = new CompositeTransform();
            element.RenderTransform = transform;
        }
        element.RenderTransformOrigin = new global::Windows.Foundation.Point(0.5, 0.5);

        var completion = new TaskCompletionSource<bool>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var storyboard = new Storyboard();
        var easing = new QuinticEase
        {
            EasingMode = entering ? EasingMode.EaseOut : EasingMode.EaseIn
        };
        var duration = new Duration(TimeSpan.FromMilliseconds(durationMs));

        var opacity = new DoubleAnimation
        {
            From = entering ? 0 : element.Opacity,
            To = entering ? 1 : 0,
            Duration = duration,
            EasingFunction = easing
        };
        Storyboard.SetTarget(opacity, element);
        Storyboard.SetTargetProperty(opacity, nameof(UIElement.Opacity));

        var translate = new DoubleAnimation
        {
            From = entering ? fromX : 0,
            To = entering ? 0 : fromX,
            Duration = duration,
            EasingFunction = easing
        };
        Storyboard.SetTarget(translate, transform);
        Storyboard.SetTargetProperty(translate, nameof(CompositeTransform.TranslateX));

        storyboard.Children.Add(opacity);
        storyboard.Children.Add(translate);
        storyboard.Completed += (_, _) =>
        {
            element.Opacity = entering ? 1 : 0;
            transform.TranslateX = entering ? 0 : fromX;
            completion.TrySetResult(true);
        };
        storyboard.Begin();
        await completion.Task;
    }

    private async Task OpenRowAsync(SessionRowViewModel row)
    {
        if (row.IsEditing)
        {
            return;
        }

        await AnimateElementAsync(ListPanel, entering: false, fromX: -3, durationMs: 90);
        _viewModel.SelectSession(row);
        await AnimateElementAsync(DetailPanel, entering: true, fromX: 3, durationMs: 170);
    }

    private async void CollapseButton_Click(object sender, RoutedEventArgs e)
    {
        await AnimateElementAsync(ExpandedPanel, entering: false, fromX: 7, durationMs: 110);
        _viewModel.Collapse();
    }

    private async void ExpandButton_Click(object sender, RoutedEventArgs e)
    {
        await AnimateElementAsync(CollapsedPanel, entering: false, fromX: 3, durationMs: 90);
        _viewModel.Expand();
    }

    private async void SessionList_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is SessionRowViewModel row)
        {
            await OpenRowAsync(row);
        }
    }

    private async void DetailBackButton_Click(object sender, RoutedEventArgs e)
    {
        await AnimateElementAsync(DetailPanel, entering: false, fromX: 3, durationMs: 90);
        _viewModel.ShowList();
        await AnimateElementAsync(ListPanel, entering: true, fromX: -3, durationMs: 150);
    }

    private async void StatusFilter_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string value }
            || !Enum.TryParse<StatusFilter>(value, out var filter))
        {
            return;
        }

        if (!_viewModel.IsShowingDetail)
        {
            await AnimateElementAsync(ListPanel, entering: false, fromX: -2, durationMs: 65);
        }
        _viewModel.SetStatusFilter(filter);
        UpdateFilterVisuals();
        await AnimateElementAsync(ListPanel, entering: true, fromX: 3, durationMs: 145);
    }

    private async void ProviderFilter_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string value }
            || !Enum.TryParse<ProviderFilter>(value, out var filter))
        {
            return;
        }

        if (!_viewModel.IsShowingDetail)
        {
            await AnimateElementAsync(ListPanel, entering: false, fromX: -2, durationMs: 65);
        }
        _viewModel.SetProviderFilter(filter);
        UpdateFilterVisuals();
        await AnimateElementAsync(ListPanel, entering: true, fromX: 3, durationMs: 145);
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        await _viewModel.RefreshAsync();
        UpdateFilterVisuals();
    }

    private void PinButton_Click(object sender, RoutedEventArgs e)
    {
        _viewModel.TogglePositionLock();
        UpdateTrayMenu();
    }

    private void PrivacyButton_Click(object sender, RoutedEventArgs e)
    {
        _viewModel.TogglePrivacy();
        UpdateFilterVisuals();
        UpdateTrayMenu();
    }

    private async void SettingsButton_Click(object sender, RoutedEventArgs e)
    {
        await ShowAISettingsAsync();
    }

    private void HideButton_Click(object sender, RoutedEventArgs e) => HideToTray();

    private void StarButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: SessionRowViewModel row })
        {
            _viewModel.ToggleImportance(row);
            UpdateFilterVisuals();
        }
    }

    private void InlineEditButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: SessionRowViewModel row })
        {
            _viewModel.BeginTitleEdit(row);
        }
    }

    private void DetailEditTitleButton_Click(object sender, RoutedEventArgs e)
    {
        if (_viewModel.SelectedRow is { } row)
        {
            _viewModel.BeginTitleEdit(row);
        }
    }

    private void CommitTitleButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: SessionRowViewModel row })
        {
            _viewModel.SaveTitleEdit(row);
            UpdateFilterVisuals();
        }
    }

    private void CancelTitleButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: SessionRowViewModel row })
        {
            _viewModel.CancelTitleEdit(row);
        }
    }

    private void TitleEditor_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (sender is not TextBox { DataContext: SessionRowViewModel row })
        {
            return;
        }
        if (e.Key == global::Windows.System.VirtualKey.Enter)
        {
            _viewModel.SaveTitleEdit(row);
            e.Handled = true;
        }
        else if (e.Key == global::Windows.System.VirtualKey.Escape)
        {
            _viewModel.CancelTitleEdit(row);
            e.Handled = true;
        }
    }

    private void ClearManualTitleButton_Click(object sender, RoutedEventArgs e)
    {
        _viewModel.ClearManualTitle();
    }

    private void OpenProjectButton_Click(object sender, RoutedEventArgs e)
    {
        _viewModel.OpenProject();
    }

    private void LoadMoreButton_Click(object sender, RoutedEventArgs e)
    {
        _viewModel.LoadMoreRuns();
    }

    private async void PromptImageButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: PromptImageViewModel image }
            || _viewModel.SelectedRow is not { } row)
        {
            return;
        }

        var dialog = new ImagePreviewDialog(
            row.PromptImages.ToArray(),
            image.Index)
        {
            XamlRoot = RootBorder.XamlRoot
        };
        await dialog.ShowAsync();
    }

    private async void ImportantRevealButton_Click(object sender, RoutedEventArgs e)
    {
        _viewModel.RevealImportantNotice();
        UpdateFilterVisuals();
        if (_viewModel.IsShowingDetail)
        {
            await AnimateElementAsync(DetailPanel, entering: true, fromX: 10, durationMs: 180);
        }
    }

    private void ImportantDismissButton_Click(object sender, RoutedEventArgs e)
    {
        _viewModel.DismissImportantNotice();
        UpdateFilterVisuals();
    }

    private void RowHoverSurface_PointerEntered(object sender, PointerRoutedEventArgs e)
    {
        if (sender is FrameworkElement root
            && root.FindName("InlineEditButton") is Button button)
        {
            button.IsHitTestVisible = true;
            button.Opacity = 1;
        }
    }

    private void RowHoverSurface_PointerExited(object sender, PointerRoutedEventArgs e)
    {
        if (sender is FrameworkElement root
            && root.FindName("InlineEditButton") is Button button)
        {
            button.IsHitTestVisible = false;
            button.Opacity = 0;
        }
    }

    private void DragSurface_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (_viewModel.PositionLocked
            || sender is not UIElement surface
            || !e.GetCurrentPoint(surface).Properties.IsLeftButtonPressed
            || IsInteractiveSource(e.OriginalSource as DependencyObject, surface))
        {
            return;
        }

        ReleaseCapture();
        SendMessage(_windowHandle, WmNcLButtonDown, (IntPtr)HtCaption, IntPtr.Zero);
    }

    private static bool IsInteractiveSource(DependencyObject? source, DependencyObject boundary)
    {
        var current = source;
        while (current is not null && !ReferenceEquals(current, boundary))
        {
            if (current is Button
                or TextBox
                or ToggleSwitch
                or CheckBox
                or ScrollBar)
            {
                return true;
            }
            current = VisualTreeHelper.GetParent(current);
        }
        return false;
    }

    private void RootBorder_ActualThemeChanged(FrameworkElement sender, object args)
    {
        ApplyWindowBackground();
        _viewModel.RefreshTheme();
        UpdateFilterVisuals();
    }

    private void ApplyWindowBackground()
    {
        var accessibility = new AccessibilitySettings();
        var highContrast = accessibility.HighContrast;
        if (_usesSystemBackdrop && !highContrast)
        {
            RootBorder.Background = new SolidColorBrush(Colors.Transparent);
            return;
        }

        var color = highContrast
            ? new UISettings().GetColorValue(UIColorType.Background)
            : RootBorder.ActualTheme == ElementTheme.Dark
                ? global::Windows.UI.Color.FromArgb(255, 16, 23, 34)
                : global::Windows.UI.Color.FromArgb(255, 242, 245, 249);
        RootBorder.Background = new SolidColorBrush(color);
    }

    private void ViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(MainViewModel.FooterText)
            or nameof(MainViewModel.WorkingCount)
            or nameof(MainViewModel.WaitingCount)
            or nameof(MainViewModel.CompletedCount)
            or nameof(MainViewModel.FailedCount)
            or nameof(MainViewModel.VisibleSessions))
        {
            DispatcherQueue.TryEnqueue(UpdateFilterVisuals);
        }
    }

    private void UpdateFilterVisuals()
    {
        var selectedStyle = ResourceStyle("HudFilterSelectedButtonStyle");
        var normalStyle = ResourceStyle("HudFilterButtonStyle");
        SetFilterStyle(StatusAllButton, StatusFilter.All, selectedStyle, normalStyle);
        SetFilterStyle(StatusWorkingButton, StatusFilter.Working, selectedStyle, normalStyle);
        SetFilterStyle(StatusWaitingButton, StatusFilter.Waiting, selectedStyle, normalStyle);
        SetFilterStyle(StatusCompletedButton, StatusFilter.Completed, selectedStyle, normalStyle);
        SetFilterStyle(StatusFailedButton, StatusFilter.Failed, selectedStyle, normalStyle);

        var selectedProviderStyle = ResourceStyle("HudFilterSelectedButtonStyle");
        SetFilterStyle(ProviderAllButton, ProviderFilter.All, selectedProviderStyle, normalStyle);
        SetFilterStyle(ProviderCodexButton, ProviderFilter.Codex, selectedProviderStyle, normalStyle);
        SetFilterStyle(ProviderClaudeButton, ProviderFilter.Claude, selectedProviderStyle, normalStyle);
        SetFilterStyle(ProviderPiButton, ProviderFilter.Pi, selectedProviderStyle, normalStyle);

        StatusAllCount.Text = _viewModel.StatusCount(StatusFilter.All);
        StatusWorkingCount.Text = _viewModel.StatusCount(StatusFilter.Working);
        StatusWaitingCount.Text = _viewModel.StatusCount(StatusFilter.Waiting);
        StatusCompletedCount.Text = _viewModel.StatusCount(StatusFilter.Completed);
        StatusFailedCount.Text = _viewModel.StatusCount(StatusFilter.Failed);

        ProviderAllCount.Text = _viewModel.ProviderCount(ProviderFilter.All);
        ProviderCodexCount.Text = _viewModel.ProviderCount(ProviderFilter.Codex);
        ProviderClaudeCount.Text = _viewModel.ProviderCount(ProviderFilter.Claude);
        ProviderPiCount.Text = _viewModel.ProviderCount(ProviderFilter.Pi);
    }

    private void SetFilterStyle<TSetting>(
        Button button,
        TSetting setting,
        Style selectedStyle,
        Style normalStyle)
        where TSetting : struct, Enum
    {
        var selected = setting switch
        {
            StatusFilter status => status == _viewModel.StatusFilter,
            ProviderFilter provider => provider == _viewModel.ProviderFilter,
            _ => false
        };
        button.Style = selected ? selectedStyle : normalStyle;
    }

    private static Style ResourceStyle(string key) =>
        (Style)Microsoft.UI.Xaml.Application.Current.Resources[key];

    private void ViewModel_CompletionTransition(
        object? sender,
        CompletionTransitionEventArgs e)
    {
        var row = _viewModel.VisibleSessions.FirstOrDefault(item => item.Session.Id == e.SessionId);
        if (row is null)
        {
            return;
        }
        if (e.IsArrival)
        {
            SessionList.ScrollIntoView(row);
        }
        DispatcherQueue.TryEnqueue(async () =>
        {
            await Task.Delay(e.IsArrival ? 35 : 0);
            if (SessionList.ContainerFromItem(row) is ListViewItem container)
            {
                await AnimateCompletionContainerAsync(container, e.IsArrival);
            }
        });
    }

    private static async Task AnimateCompletionContainerAsync(
        ListViewItem container,
        bool arrival)
    {
        if (container.RenderTransform is not CompositeTransform transform)
        {
            transform = new CompositeTransform();
            container.RenderTransform = transform;
        }
        var completion = new TaskCompletionSource<bool>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var storyboard = new Storyboard();
        var easing = new QuinticEase
        {
            EasingMode = arrival ? EasingMode.EaseOut : EasingMode.EaseIn
        };
        var duration = new Duration(TimeSpan.FromMilliseconds(arrival ? 340 : 400));

        var opacity = new DoubleAnimation
        {
            From = arrival ? 0 : 1,
            To = arrival ? 1 : 0,
            Duration = duration,
            EasingFunction = easing
        };
        Storyboard.SetTarget(opacity, container);
        Storyboard.SetTargetProperty(opacity, nameof(UIElement.Opacity));

        var x = new DoubleAnimation
        {
            From = arrival ? 0 : 0,
            To = arrival ? 0 : 48,
            Duration = duration,
            EasingFunction = easing
        };
        Storyboard.SetTarget(x, transform);
        Storyboard.SetTargetProperty(x, nameof(CompositeTransform.TranslateX));

        var y = new DoubleAnimation
        {
            From = arrival ? 16 : 0,
            To = arrival ? 0 : 0,
            Duration = duration,
            EasingFunction = easing
        };
        Storyboard.SetTarget(y, transform);
        Storyboard.SetTargetProperty(y, nameof(CompositeTransform.TranslateY));

        storyboard.Children.Add(opacity);
        storyboard.Children.Add(x);
        storyboard.Children.Add(y);
        storyboard.Completed += (_, _) =>
        {
            container.Opacity = 1;
            transform.TranslateX = 0;
            transform.TranslateY = 0;
            completion.TrySetResult(true);
        };
        storyboard.Begin();
        await completion.Task;
    }

    private void AppWindow_Changed(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (args.DidPositionChange && !_isAnimatingWindow)
        {
            SaveWindowPositionSoon();
        }
    }

    private void SaveWindowPositionSoon()
    {
        _positionSaveTimer.Stop();
        _positionSaveTimer.Start();
    }

    private void SaveWindowPosition()
    {
        var position = _appWindow.Position;
        _viewModel.SaveWindowPosition(position.X, position.Y);
    }

    private void AppWindow_Closing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (_allowClose)
        {
            return;
        }
        args.Cancel = true;
        HideToTray();
    }

    private void HideToTray()
    {
        SaveWindowPosition();
        _appWindow.Hide();
        UpdateTrayMenu();
    }

    private void ShowHud()
    {
        _appWindow.Show();
        Activate();
        UpdateTrayMenu();
    }

    private void ToggleVisibility()
    {
        if (IsWindowVisible(_windowHandle))
        {
            HideToTray();
        }
        else
        {
            ShowHud();
        }
    }

    private async void ToggleExpanded()
    {
        ShowHud();
        if (_viewModel.IsExpanded)
        {
            await AnimateElementAsync(ExpandedPanel, entering: false, fromX: 3, durationMs: 90);
            _viewModel.Collapse();
        }
        else
        {
            await AnimateElementAsync(CollapsedPanel, entering: false, fromX: 3, durationMs: 90);
            _viewModel.Expand();
        }
    }

    private void TogglePrivacy()
    {
        _viewModel.TogglePrivacy();
        UpdateFilterVisuals();
        UpdateTrayMenu();
    }

    private void TogglePositionLock()
    {
        _viewModel.TogglePositionLock();
        UpdateTrayMenu();
    }

    private async void RefreshFromTray()
    {
        await _viewModel.RefreshAsync();
        UpdateFilterVisuals();
    }

    private void OpenSettingsFromTray()
    {
        ShowHud();
        DispatcherQueue.TryEnqueue(async () => await ShowAISettingsAsync());
    }

    private async Task ShowAISettingsAsync()
    {
        var dialog = new AISettingsDialog(_viewModel)
        {
            XamlRoot = RootBorder.XamlRoot
        };
        await dialog.ShowAsync();
    }

    private void UpdateTrayMenu()
    {
        // The native tray menu reads the current state whenever it opens.
    }

    private void ExitApplication()
    {
        _allowClose = true;
        _trayIcon.Dispose();
        _viewModel.Stop();
        Close();
        Microsoft.UI.Xaml.Application.Current.Exit();
    }

    private void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        _resizeAnimation?.Cancel();
        _resizeAnimation?.Dispose();
        _contentTransition?.Cancel();
        _contentTransition?.Dispose();
        _positionSaveTimer.Stop();
        _trayIcon.Dispose();
        _viewModel.Stop();
    }

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessage(
        IntPtr hWnd,
        int msg,
        IntPtr wParam,
        IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);
}
