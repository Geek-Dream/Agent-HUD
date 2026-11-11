using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.CompilerServices;
using AgentHUD.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage.Streams;

namespace AgentHUD.Windows;

public sealed class CompletionTransitionEventArgs : EventArgs
{
    public CompletionTransitionEventArgs(string sessionId, bool isArrival)
    {
        SessionId = sessionId;
        IsArrival = isArrival;
    }

    public string SessionId { get; }
    public bool IsArrival { get; }
}

public sealed class MainViewModel : INotifyPropertyChanged
{
    private readonly AppStateStore _store;
    private readonly CredentialStore _credentials;
    private readonly SessionScanner _scanner = new();
    private readonly AITitleService _aiTitleService = new();
    private readonly SessionTitleResolver _titleResolver = new();
    private readonly Dictionary<string, string> _aiTitles = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _aiKeys = new(StringComparer.Ordinal);
    private readonly SemaphoreSlim _refreshGate = new(1, 1);
    private CancellationTokenSource? _loopCancellation;
    private Task? _aiTask;
    private IReadOnlyList<AgentSession> _sessions = Array.Empty<AgentSession>();
    private SessionRowViewModel? _selectedRow;
    private ImportantCompletionNotice? _importantNotice;
    private bool _isLoading;
    private bool _isExpanded;
    private bool _privacyMode;
    private bool _positionLocked;
    private int _runVisibleCount = 5;
    private string _lastFingerprint = string.Empty;

    public MainViewModel()
    {
        _store = App.StateStore;
        _credentials = App.Credentials;
        var state = _store.State;
        _isExpanded = state.IsExpanded;
        _privacyMode = state.PrivacyMode;
        _positionLocked = state.PositionLocked;
        StatusFilter = state.StatusFilter;
        ProviderFilter = state.ProviderFilter;
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler? ExpansionStateChanged;
    public event EventHandler<CompletionTransitionEventArgs>? CompletionTransition;
    public event EventHandler? SettingsRequested;
    public event EventHandler? HideRequested;

    public ObservableCollection<SessionRowViewModel> VisibleSessions { get; } = new();
    public StatusFilter StatusFilter { get; private set; }
    public ProviderFilter ProviderFilter { get; private set; }
    public DateTimeOffset? LastScannedAt { get; private set; }
    public AIConfiguration AIConfiguration => _store.State.AI.Clone();
    public bool HasApiKey => !string.IsNullOrWhiteSpace(_credentials.GetApiKey());
    public string? GetSavedApiKey() => _credentials.GetApiKey();

    public SessionRowViewModel? SelectedRow
    {
        get => _selectedRow;
        private set
        {
            if (ReferenceEquals(_selectedRow, value))
            {
                return;
            }
            _selectedRow = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(IsShowingDetail));
            OnPropertyChanged(nameof(ListVisibility));
            OnPropertyChanged(nameof(DetailVisibility));
        }
    }

    public bool IsShowingDetail => SelectedRow is not null;
    public Visibility ListVisibility => SelectedRow is null ? Visibility.Visible : Visibility.Collapsed;
    public Visibility DetailVisibility => SelectedRow is null ? Visibility.Collapsed : Visibility.Visible;

    public bool IsExpanded
    {
        get => _isExpanded;
        private set
        {
            if (_isExpanded == value)
            {
                return;
            }
            _isExpanded = value;
            _store.State.IsExpanded = value;
            _store.Save();
            OnPropertyChanged();
            OnPropertyChanged(nameof(CollapsedVisibility));
            OnPropertyChanged(nameof(ExpandedVisibility));
            ExpansionStateChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    public Visibility CollapsedVisibility => IsExpanded ? Visibility.Collapsed : Visibility.Visible;
    public Visibility ExpandedVisibility => IsExpanded ? Visibility.Visible : Visibility.Collapsed;

    public bool PrivacyMode
    {
        get => _privacyMode;
        private set
        {
            if (_privacyMode == value)
            {
                return;
            }
            _privacyMode = value;
            _store.State.PrivacyMode = value;
            _store.Save();
            OnPropertyChanged();
            OnPropertyChanged(nameof(PrivacyStripVisibility));
            OnPropertyChanged(nameof(PrivacyGlyph));
            OnPropertyChanged(nameof(CompactDisplayText));
            OnPropertyChanged(nameof(ImportantNoticeText));
            RebuildRows(force: true);
        }
    }

    public Visibility PrivacyStripVisibility =>
        PrivacyMode ? Visibility.Visible : Visibility.Collapsed;

    public string PrivacyGlyph => PrivacyMode ? "\uED1A" : "\uE7B3";

    public bool PositionLocked
    {
        get => _positionLocked;
        private set
        {
            if (_positionLocked == value)
            {
                return;
            }
            _positionLocked = value;
            _store.State.PositionLocked = value;
            _store.Save();
            OnPropertyChanged();
            OnPropertyChanged(nameof(PinGlyph));
        }
    }

    public string PinGlyph => PositionLocked ? "\uE840" : "\uE718";

    public bool IsLoading
    {
        get => _isLoading;
        private set
        {
            if (_isLoading == value)
            {
                return;
            }
            _isLoading = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(LoadingVisibility));
            OnPropertyChanged(nameof(RefreshGlyph));
        }
    }

    public Visibility LoadingVisibility =>
        IsLoading && _sessions.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

    public Visibility EmptyVisibility =>
        !IsLoading && VisibleSessions.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

    public Visibility ListContentVisibility =>
        VisibleSessions.Count > 0 ? Visibility.Visible : Visibility.Collapsed;

    public string RefreshGlyph => IsLoading ? "\uE895" : "\uE72C";

    public string ActiveSummary
    {
        get
        {
            var active = _sessions.Count(session => session.Status.IsActive());
            return active > 0 ? $"{active} 个 Agent 正在进行" : "本地只读监视中";
        }
    }

    public string CompactStatusText
    {
        get
        {
            if (_sessions.Count == 0)
            {
                return IsLoading ? "正在读取本地会话" : "等待本地 Agent";
            }
            var active = _sessions.FirstOrDefault(session => session.Status.IsActive());
            if (active is not null)
            {
                return DisplayTitle(active);
            }
            return DisplayTitle(_sessions[0]);
        }
    }

    public string CompactDisplayText => PrivacyMode ? "隐私模式已开启" : CompactStatusText;

    public string FooterText => LastScannedAt is null
        ? "正在读取"
        : $"更新于 {LastScannedAt.Value:HH:mm:ss}";

    public int WorkingCount => _sessions.Count(session =>
        session.Status is AgentStatus.Working or AgentStatus.Starting);
    public int WaitingCount => _sessions.Count(session => session.Status == AgentStatus.WaitingUser);
    public int CompletedCount => _sessions.Count(session => session.Status == AgentStatus.Completed);
    public int FailedCount => _sessions.Count(session => session.Status == AgentStatus.Failed);

    public string StatusCount(StatusFilter filter) =>
        _sessions.Count(session =>
            ProviderFilter.Matches(session.Provider) && filter.Matches(session.Status)).ToString();

    public string ProviderCount(ProviderFilter filter) =>
        _sessions.Count(session =>
            StatusFilter.Matches(session.Status) && filter.Matches(session.Provider)).ToString();

    public Visibility ImportantNoticeVisibility =>
        _importantNotice is null ? Visibility.Collapsed : Visibility.Visible;

    public string ImportantNoticeText => _importantNotice is null
        ? string.Empty
        : PrivacyMode
            ? $"{_importantNotice.Provider.DisplayName()} 的重要会话已完成 · 标题已隐藏"
            : $"{_importantNotice.Provider.DisplayName()} 的重要会话已完成 · {_importantNotice.Title}";

    public string SelectedRunCountText => SelectedRow is null
        ? "0 轮"
        : $"{SelectedRow.TotalRunCount} 轮";

    public Visibility LoadMoreVisibility => SelectedRow?.HasMoreRuns == true
        ? Visibility.Visible
        : Visibility.Collapsed;

    public void Start()
    {
        if (_loopCancellation is not null)
        {
            return;
        }
        _loopCancellation = new CancellationTokenSource();
        _ = RefreshLoopAsync(_loopCancellation.Token);
    }

    public void Stop()
    {
        _loopCancellation?.Cancel();
        _loopCancellation?.Dispose();
        _loopCancellation = null;
        _aiTitleService.Dispose();
    }

    public async Task RefreshAsync()
    {
        if (!await _refreshGate.WaitAsync(0))
        {
            return;
        }

        try
        {
            IsLoading = true;
            var snapshot = await Task.Run(() => _scanner.Scan());
            var previous = _sessions;
            var completionIds = SessionTransitionDetector.RunningCompletionIds(previous, snapshot.Sessions);
            var animatedIds = StatusFilter == StatusFilter.All
                ? completionIds.Where(id =>
                {
                    var session = snapshot.Sessions.FirstOrDefault(item => item.Id == id);
                    return session is not null && ProviderFilter.Matches(session.Provider);
                }).ToArray()
                : Array.Empty<string>();

            if (animatedIds.Length > 0)
            {
                foreach (var id in animatedIds)
                {
                    CompletionTransition?.Invoke(this, new CompletionTransitionEventArgs(id, false));
                }
                await Task.Delay(440);
            }

            _sessions = snapshot.Sessions;
            LastScannedAt = snapshot.ScannedAt;
            PresentImportantCompletionIfNeeded(previous, snapshot.Sessions, completionIds);
            RebuildRows(force: animatedIds.Length > 0);
            IsLoading = false;

            if (animatedIds.Length > 0)
            {
                await Task.Delay(35);
                foreach (var id in animatedIds)
                {
                    CompletionTransition?.Invoke(this, new CompletionTransitionEventArgs(id, true));
                }
            }

            StartAIEnrichment();
        }
        finally
        {
            IsLoading = false;
            _refreshGate.Release();
        }
    }

    public void SetStatusFilter(StatusFilter filter)
    {
        if (StatusFilter == filter)
        {
            return;
        }
        StatusFilter = filter;
        _store.State.StatusFilter = filter;
        _store.Save();
        OnPropertyChanged(nameof(StatusFilter));
        SelectedRow = null;
        DismissImportantNoticeIfVisible();
        RebuildRows(force: true);
    }

    public void SetProviderFilter(ProviderFilter filter)
    {
        if (ProviderFilter == filter)
        {
            return;
        }
        ProviderFilter = filter;
        _store.State.ProviderFilter = filter;
        _store.Save();
        OnPropertyChanged(nameof(ProviderFilter));
        SelectedRow = null;
        DismissImportantNoticeIfVisible();
        RebuildRows(force: true);
    }

    public void SelectSession(SessionRowViewModel row)
    {
        if (row.IsEditing)
        {
            return;
        }
        _runVisibleCount = 5;
        SelectedRow = CreateDetailRow(row.Session);
        OnPropertyChanged(nameof(SelectedRunCountText));
        OnPropertyChanged(nameof(LoadMoreVisibility));
    }

    public void ShowList()
    {
        SelectedRow = null;
    }

    public void Collapse()
    {
        SelectedRow = null;
        IsExpanded = false;
    }

    public void Expand() => IsExpanded = true;

    public void Hide() => HideRequested?.Invoke(this, EventArgs.Empty);

    public void OpenSettings() => SettingsRequested?.Invoke(this, EventArgs.Empty);

    public void TogglePositionLock() => PositionLocked = !PositionLocked;

    public void TogglePrivacy() => PrivacyMode = !PrivacyMode;

    public void RefreshTheme() => RebuildRows(force: true);

    public void ToggleImportance(SessionRowViewModel row)
    {
        _store.ToggleImportant(row.Session.Id);
        RebuildRows(force: true);
    }

    public bool IsImportant(AgentSession session) =>
        _store.State.ImportantSessionIds.Contains(session.Id);

    public void BeginTitleEdit(SessionRowViewModel row)
    {
        row.BeginEdit();
    }

    public void SaveTitleEdit(SessionRowViewModel row)
    {
        _store.SetManualTitle(row.Session.Id, row.EditDraft);
        row.EndEdit();
        RebuildRows(force: true);
    }

    public void CancelTitleEdit(SessionRowViewModel row)
    {
        row.CancelEdit();
    }

    public void ClearManualTitle()
    {
        if (SelectedRow is null)
        {
            return;
        }
        _store.SetManualTitle(SelectedRow.Session.Id, null);
        RebuildRows(force: true);
        SelectedRow = CreateDetailRow(SelectedRow.Session);
    }

    public void LoadMoreRuns()
    {
        if (SelectedRow is null)
        {
            return;
        }
        _runVisibleCount = Math.Min(SelectedRow.TotalRunCount, _runVisibleCount + 5);
        SelectedRow.UpdateVisibleRuns(_runVisibleCount, PrivacyMode);
        OnPropertyChanged(nameof(LoadMoreVisibility));
    }

    public void OpenProject()
    {
        if (SelectedRow is null || PrivacyMode || !Directory.Exists(SelectedRow.Session.ProjectPath))
        {
            return;
        }
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"\"{SelectedRow.Session.ProjectPath}\"",
                UseShellExecute = true
            });
        }
        catch
        {
        }
    }

    public void RevealImportantNotice()
    {
        if (_importantNotice is null)
        {
            return;
        }
        var sessionId = _importantNotice.SessionId;
        _importantNotice = null;
        NotifyImportantNotice();
        SetStatusFilter(StatusFilter.All);
        SetProviderFilter(ProviderFilter.All);
        RebuildRows(force: true);
        var row = VisibleSessions.FirstOrDefault(item => item.Session.Id == sessionId);
        if (row is not null)
        {
            SelectSession(row);
        }
    }

    public void DismissImportantNotice()
    {
        _importantNotice = null;
        NotifyImportantNotice();
    }

    public void SaveAIConfiguration(AIConfiguration configuration, string? apiKey)
    {
        _store.State.AI = configuration.Clone();
        _store.Save();
        if (apiKey is not null)
        {
            _credentials.SaveApiKey(apiKey);
        }
        OnPropertyChanged(nameof(HasApiKey));
        _aiTitles.Clear();
        _aiKeys.Clear();
        _aiTask = null;
        _aiTitleService.ClearCache();
        RebuildRows(force: true);
        StartAIEnrichment();
    }

    public void ClearApiKey()
    {
        _credentials.DeleteApiKey();
        _store.State.AI.Enabled = false;
        _store.Save();
        _aiTitles.Clear();
        _aiKeys.Clear();
        _aiTask = null;
        _aiTitleService.ClearCache();
        OnPropertyChanged(nameof(HasApiKey));
        OnPropertyChanged(nameof(AIConfiguration));
        RebuildRows(force: true);
    }

    public async Task TestAIConnectionAsync(
        AIConfiguration configuration,
        string apiKey,
        CancellationToken cancellationToken)
    {
        await _aiTitleService.TestConnectionAsync(configuration, apiKey, cancellationToken);
    }

    public void SaveWindowPosition(int x, int y)
    {
        _store.State.WindowX = x;
        _store.State.WindowY = y;
        _store.Save();
    }

    public (int? X, int? Y) SavedWindowPosition => (
        _store.State.WindowX is { } x ? (int)x : null,
        _store.State.WindowY is { } y ? (int)y : null);

    public (double? Width, double? Height) SavedExpandedWindowSize => (
        _store.State.ExpandedWidth,
        _store.State.ExpandedHeight);

    public void SaveExpandedWindowSize(double width, double height)
    {
        _store.State.ExpandedWidth = width;
        _store.State.ExpandedHeight = height;
        _store.Save();
    }

    private async Task RefreshLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            await RefreshAsync();
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(3), cancellationToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    private void RebuildRows(bool force)
    {
        var manual = _store.State.ManualTitles;
        var important = _store.State.ImportantSessionIds;
        var filtered = _sessions
            .Where(session =>
                StatusFilter.Matches(session.Status)
                && ProviderFilter.Matches(session.Provider))
            .ToArray();
        var ordered = SessionOrdering.Sort(
            filtered,
            important,
            runningFirst: StatusFilter == StatusFilter.All);

        var fingerprint = string.Join(
            "\u001E",
            StatusFilter,
            ProviderFilter,
            PrivacyMode,
            string.Join("\u001F", ordered.Select(session =>
                $"{session.Id}:{session.Status}:{session.LastActivityAt.UtcTicks}:{DisplayTitle(session)}:{important.Contains(session.Id)}")));
        if (!force && fingerprint == _lastFingerprint)
        {
            NotifyCounts();
            return;
        }
        _lastFingerprint = fingerprint;

        var selectedId = SelectedRow?.Session.Id;
        VisibleSessions.Clear();
        foreach (var session in ordered)
        {
            VisibleSessions.Add(CreateRow(session));
        }

        if (selectedId is not null)
        {
            var updated = _sessions.FirstOrDefault(session => session.Id == selectedId);
            SelectedRow = updated is null ? null : CreateDetailRow(updated);
        }

        NotifyCounts();
        OnPropertyChanged(nameof(EmptyVisibility));
        OnPropertyChanged(nameof(ListContentVisibility));
        OnPropertyChanged(nameof(CompactStatusText));
        OnPropertyChanged(nameof(CompactDisplayText));
        OnPropertyChanged(nameof(ActiveSummary));
        OnPropertyChanged(nameof(FooterText));
    }

    private SessionRowViewModel CreateRow(AgentSession session)
    {
        var title = ResolveTitle(session);
        var row = new SessionRowViewModel(
            session,
            PrivacyMode ? "任务标题已隐藏" : title.Value,
            title.Source,
            IsImportant(session),
            PrivacyMode);
        return row;
    }

    private SessionRowViewModel CreateDetailRow(AgentSession session)
    {
        var title = ResolveTitle(session);
        var row = new SessionRowViewModel(
            session,
            PrivacyMode ? "任务标题已隐藏" : title.Value,
            title.Source,
            IsImportant(session),
            PrivacyMode);
        row.LoadPromptImages();
        row.UpdateVisibleRuns(_runVisibleCount, PrivacyMode);
        return row;
    }

    private ResolvedTitle ResolveTitle(AgentSession session) =>
        _titleResolver.Resolve(
            session.Id,
            session.Title,
            _store.State.ManualTitles,
            _aiTitles);

    private string DisplayTitle(AgentSession session) => ResolveTitle(session).Value;

    private void PresentImportantCompletionIfNeeded(
        IReadOnlyList<AgentSession> previous,
        IReadOnlyList<AgentSession> current,
        IReadOnlySet<string> completionIds)
    {
        var previousById = previous.ToDictionary(session => session.Id);
        foreach (var session in current
            .Where(session => completionIds.Contains(session.Id))
            .OrderByDescending(session => session.LastActivityAt))
        {
            if (!previousById.TryGetValue(session.Id, out var old)
                || old.Status is not (AgentStatus.Working or AgentStatus.Starting)
                || session.Status != AgentStatus.Completed
                || !_store.State.ImportantSessionIds.Contains(session.Id))
            {
                continue;
            }

            var visible = StatusFilter.Matches(session.Status)
                && ProviderFilter.Matches(session.Provider);
            if (visible)
            {
                continue;
            }

            _importantNotice = new ImportantCompletionNotice(
                session.Id,
                session.Provider,
                DisplayTitle(session),
                session.ProjectName);
            NotifyImportantNotice();
            return;
        }
    }

    private void DismissImportantNoticeIfVisible()
    {
        if (_importantNotice is null
            || !StatusFilter.Matches(AgentStatus.Completed)
            || !ProviderFilter.Matches(_importantNotice.Provider))
        {
            return;
        }
        _importantNotice = null;
        NotifyImportantNotice();
    }

    private void NotifyImportantNotice()
    {
        OnPropertyChanged(nameof(ImportantNoticeVisibility));
        OnPropertyChanged(nameof(ImportantNoticeText));
    }

    private void StartAIEnrichment()
    {
        if (_aiTask is { IsCompleted: false })
        {
            return;
        }

        var configuration = _store.State.AI;
        var apiKey = _credentials.GetApiKey();
        if (!configuration.IsUsable || string.IsNullOrWhiteSpace(apiKey))
        {
            return;
        }

        var requests = _sessions
            .Where(session => !_store.State.ManualTitles.ContainsKey(session.Id))
            .Select(session =>
            {
                var prompt = session.LatestUserPrompt;
                if (prompt is null)
                {
                    return null;
                }
                var meaningful = TextTools.MeaningfulPrompt(prompt.Text);
                if (meaningful is null && prompt.Images.Count == 0)
                {
                    return null;
                }
                if (meaningful is not null
                    && TextTools.IsContinuationPrompt(meaningful)
                    && prompt.Images.Count == 0)
                {
                    return null;
                }
                return new AITitleRequest(
                    session.Id,
                    meaningful ?? string.Empty,
                    session.ProjectName,
                    prompt.Images);
            })
            .Where(request => request is not null)
            .Cast<AITitleRequest>()
            .ToArray();

        if (requests.Length == 0)
        {
            return;
        }

        _aiTask = EnrichTitlesAsync(requests, configuration, apiKey);
    }

    private async Task EnrichTitlesAsync(
        IReadOnlyList<AITitleRequest> requests,
        AIConfiguration configuration,
        string apiKey)
    {
        foreach (var request in requests)
        {
            var key = $"{request.SessionId}:{request.Prompt}:{request.Images.Count}";
            if (_aiKeys.TryGetValue(request.SessionId, out var oldKey) && oldKey == key)
            {
                continue;
            }
            try
            {
                var title = await _aiTitleService.GetTitleAsync(
                    request,
                    configuration,
                    apiKey,
                    CancellationToken.None);
                _aiTitles[request.SessionId] = title;
                _aiKeys[request.SessionId] = key;
                RebuildRows(force: true);
            }
            catch
            {
                _aiKeys[request.SessionId] = key;
            }
        }
    }

    private void NotifyCounts()
    {
        OnPropertyChanged(nameof(WorkingCount));
        OnPropertyChanged(nameof(WaitingCount));
        OnPropertyChanged(nameof(CompletedCount));
        OnPropertyChanged(nameof(FailedCount));
        OnPropertyChanged(nameof(SelectedRunCountText));
        OnPropertyChanged(nameof(LoadMoreVisibility));
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

public sealed class SessionRowViewModel : INotifyPropertyChanged
{
    private readonly List<TaskRun> _sortedRuns;
    private bool _isEditing;
    private string _editDraft;

    public SessionRowViewModel(
        AgentSession session,
        string displayTitle,
        TitleSource titleSource,
        bool isImportant,
        bool privacyMode)
    {
        Session = session;
        DisplayTitle = displayTitle;
        TitleSource = titleSource;
        IsImportant = isImportant;
        PrivacyMode = privacyMode;
        _editDraft = displayTitle;
        _sortedRuns = session.Runs.OrderByDescending(run => run.CompletedAt).ToList();
        Runs = new ObservableCollection<RunViewModel>();
        PromptImages = new ObservableCollection<PromptImageViewModel>();
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler? TitleCommitted;

    public AgentSession Session { get; }
    public string DisplayTitle { get; }
    public TitleSource TitleSource { get; }
    public bool IsImportant { get; }
    public bool PrivacyMode { get; }
    public ObservableCollection<RunViewModel> Runs { get; }
    public ObservableCollection<PromptImageViewModel> PromptImages { get; }
    public int TotalRunCount => _sortedRuns.Count;
    public bool HasMoreRuns => Runs.Count < _sortedRuns.Count;
    public string StarGlyph => IsImportant ? "\uE735" : "\uE734";
    public string ProviderShortName => Session.Provider.ShortName();
    public string ProviderDisplayName => Session.Provider.DisplayName();
    public string ProviderInitials => Session.Provider switch
    {
        AgentProvider.Codex => "Cx",
        AgentProvider.Claude => "Cl",
        AgentProvider.Pi => "Pi",
        _ => "Ag"
    };
    public Brush ProviderBrush => BrushForProvider(Session.Provider);
    public Brush StatusBrush => BrushForStatus(Session.Status);
    public Brush StatusTintBrush => BrushForStatusTint(Session.Status);
    public string StatusLabel => Session.Status.ShortLabel();
    public string StatusLongLabel => Session.Status.Label();
    public string ConfidenceLabel => Session.Confidence.Label();
    public string ProjectName => PrivacyMode ? "项目已隐藏" : Session.ProjectName;
    public string CurrentAction => PrivacyMode ? "当前动作已隐藏" : Session.CurrentAction;
    public string ActivityAge => RelativeTime(Session.LastActivityAt);
    public string StartedAge => RelativeTime(Session.StartedAt);
    public string DurationText => CompactDuration(Session.Duration);
    public string GitText => Session.Git is null
        ? "非 Git 项目"
        : $"{Session.Git.Branch} · {Session.Git.ChangedFiles} 个改动";
    public string ProjectPath => PrivacyMode ? "项目路径已隐藏" : Session.ProjectPath;
    public string CurrentFilesText => PrivacyMode
        ? "文件已隐藏"
        : string.Join("\n", Session.CurrentFiles.Take(3).Select(path => TextTools.FileName(path)));
    public string PromptText => PrivacyMode
        ? "隐私模式已隐藏原始输入与图片"
        : Session.LatestUserPrompt?.Text ?? "尚未读取到最近一次用户输入";
    public string PromptDateText => Session.LatestUserPrompt?.SentAt is { } date
        ? date.ToLocalTime().ToString("MM-dd HH:mm")
        : "未记录时间";
    public string TitleSourceText => TitleSource.Label();
    public Visibility ManualTitleActionVisibility =>
        TitleSource == TitleSource.User ? Visibility.Visible : Visibility.Collapsed;
    public Visibility PromptImagesVisibility =>
        !PrivacyMode && PromptImages.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
    public Visibility CurrentFilesVisibility =>
        !PrivacyMode && Session.CurrentFiles.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
    public Visibility EmptyRunsVisibility =>
        Runs.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    public Visibility RunsVisibility =>
        Runs.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
    public Visibility ImportantAccentVisibility =>
        IsImportant ? Visibility.Visible : Visibility.Collapsed;
    public Visibility CompletedOutlineVisibility =>
        Session.Status == AgentStatus.Completed ? Visibility.Visible : Visibility.Collapsed;

    public bool IsEditing
    {
        get => _isEditing;
        private set
        {
            if (_isEditing == value)
            {
                return;
            }
            _isEditing = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(TitleVisibility));
            OnPropertyChanged(nameof(EditorVisibility));
        }
    }

    public string EditDraft
    {
        get => _editDraft;
        set
        {
            if (_editDraft == value)
            {
                return;
            }
            _editDraft = value;
            OnPropertyChanged();
        }
    }

    public Visibility TitleVisibility => IsEditing ? Visibility.Collapsed : Visibility.Visible;
    public Visibility EditorVisibility => IsEditing ? Visibility.Visible : Visibility.Collapsed;

    public void BeginEdit()
    {
        EditDraft = DisplayTitle;
        IsEditing = true;
    }

    public void EndEdit()
    {
        IsEditing = false;
    }

    public void CancelEdit()
    {
        EditDraft = DisplayTitle;
        IsEditing = false;
    }

    public void CommitEdit() => TitleCommitted?.Invoke(this, EventArgs.Empty);

    public void LoadPromptImages()
    {
        var prompt = Session.LatestUserPrompt;
        if (prompt is null)
        {
            return;
        }
        for (var index = 0; index < prompt.Images.Count; index++)
        {
            var image = new PromptImageViewModel(prompt.Images[index], index);
            PromptImages.Add(image);
            _ = image.LoadAsync();
        }
        OnPropertyChanged(nameof(PromptImagesVisibility));
    }

    public void UpdateVisibleRuns(int count, bool privacyMode)
    {
        Runs.Clear();
        foreach (var run in _sortedRuns.Take(count))
        {
            Runs.Add(new RunViewModel(run, privacyMode));
        }
        OnPropertyChanged(nameof(HasMoreRuns));
        OnPropertyChanged(nameof(EmptyRunsVisibility));
        OnPropertyChanged(nameof(RunsVisibility));
    }

    private static Brush BrushForProvider(AgentProvider provider) =>
        ThemeBrush(provider switch
        {
            AgentProvider.Codex => "HudCodexBrush",
            AgentProvider.Claude => "HudClaudeBrush",
            AgentProvider.Pi => "HudPiBrush",
            _ => "HudTextSecondaryBrush"
        });

    private static Brush BrushForStatus(AgentStatus status) =>
        ThemeBrush(status switch
        {
            AgentStatus.Starting or AgentStatus.Working => "HudWorkingBrush",
            AgentStatus.WaitingUser => "HudWaitingBrush",
            AgentStatus.Completed => "HudCompletedBrush",
            AgentStatus.Failed => "HudFailedBrush",
            _ => "HudTextSecondaryBrush"
        });

    private static Brush BrushForStatusTint(AgentStatus status) =>
        ThemeBrush(status switch
        {
            AgentStatus.Starting or AgentStatus.Working => "HudWorkingTintBrush",
            AgentStatus.WaitingUser => "HudWaitingTintBrush",
            AgentStatus.Completed => "HudCompletedTintBrush",
            AgentStatus.Failed => "HudFailedTintBrush",
            _ => "HudNeutralTintBrush"
        });

    private static Brush ThemeBrush(string key)
    {
        if (Microsoft.UI.Xaml.Application.Current.Resources.TryGetValue(key, out var resource)
            && resource is Brush brush)
        {
            return brush;
        }
        return new SolidColorBrush(global::Windows.UI.Color.FromArgb(255, 128, 138, 152));
    }

    private static string RelativeTime(DateTimeOffset value)
    {
        var age = DateTimeOffset.Now - value;
        if (age < TimeSpan.FromMinutes(1))
        {
            return "刚刚";
        }
        if (age < TimeSpan.FromHours(1))
        {
            return $"{Math.Max(1, (int)age.TotalMinutes)} 分钟前";
        }
        if (age < TimeSpan.FromDays(1))
        {
            return $"{Math.Max(1, (int)age.TotalHours)} 小时前";
        }
        return $"{Math.Max(1, (int)age.TotalDays)} 天前";
    }

    private static string CompactDuration(TimeSpan duration)
    {
        if (duration.TotalMinutes < 1)
        {
            return $"{Math.Max(0, (int)duration.TotalSeconds)} 秒";
        }
        if (duration.TotalHours < 1)
        {
            return $"{Math.Max(1, (int)duration.TotalMinutes)} 分钟";
        }
        return $"{Math.Max(1, (int)duration.TotalHours)} 小时";
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

public sealed class RunViewModel
{
    public RunViewModel(TaskRun run, bool privacyMode)
    {
        DateText = run.CompletedAt.ToLocalTime().ToString("MM-dd HH:mm");
        Objective = privacyMode ? "任务目标已隐藏" : run.Objective;
        Summary = privacyMode ? "完成总结已隐藏" : run.Summary;
        Actions = privacyMode ? string.Empty : string.Join("\n", run.Actions.Take(6));
        Files = privacyMode
            ? string.Empty
            : string.Join("\n", run.FilesChanged.Take(5).Select(TextTools.FileName));
        ActionsVisibility = string.IsNullOrWhiteSpace(Actions)
            ? Visibility.Collapsed
            : Visibility.Visible;
        FilesVisibility = string.IsNullOrWhiteSpace(Files)
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    public string DateText { get; }
    public string Objective { get; }
    public string Summary { get; }
    public string Actions { get; }
    public string Files { get; }
    public Visibility ActionsVisibility { get; }
    public Visibility FilesVisibility { get; }
}

public sealed class PromptImageViewModel : INotifyPropertyChanged
{
    private readonly SessionImageAttachment _attachment;
    private BitmapImage? _imageSource;
    private InMemoryRandomAccessStream? _stream;

    public PromptImageViewModel(SessionImageAttachment attachment, int index)
    {
        _attachment = attachment;
        Index = index;
        Label = SessionImageAttachment.DisplayLabel(index);
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public int Index { get; }
    public string Label { get; }
    public SessionImageAttachment Attachment => _attachment;
    public BitmapImage? ImageSource
    {
        get => _imageSource;
        private set
        {
            _imageSource = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(ImageSource)));
        }
    }

    public async Task LoadAsync()
    {
        try
        {
            if (!string.IsNullOrWhiteSpace(_attachment.LocalPath)
                && File.Exists(_attachment.LocalPath))
            {
                ImageSource = new BitmapImage(new Uri(_attachment.LocalPath));
                return;
            }
            if (string.IsNullOrWhiteSpace(_attachment.DataUrl))
            {
                return;
            }

            var comma = _attachment.DataUrl.IndexOf(',');
            if (comma < 0)
            {
                return;
            }
            var bytes = Convert.FromBase64String(_attachment.DataUrl[(comma + 1)..]);
            var stream = new InMemoryRandomAccessStream();
            using (var writer = new DataWriter(stream.GetOutputStreamAt(0)))
            {
                writer.WriteBytes(bytes);
                await writer.StoreAsync();
                await writer.FlushAsync();
                writer.DetachStream();
            }
            stream.Seek(0);
            var bitmap = new BitmapImage();
            await bitmap.SetSourceAsync(stream);
            _stream = stream;
            ImageSource = bitmap;
        }
        catch
        {
            ImageSource = null;
        }
    }
}
