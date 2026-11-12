using System.Text.Json;
using System.Text.Json.Serialization;

namespace AgentHUD.Core;

public sealed class PersistedAppState
{
    public bool IsExpanded { get; set; }
    public bool PrivacyMode { get; set; }
    public bool PositionLocked { get; set; }
    public StatusFilter StatusFilter { get; set; } = StatusFilter.All;
    public ProviderFilter ProviderFilter { get; set; } = ProviderFilter.All;
    public double? WindowX { get; set; }
    public double? WindowY { get; set; }
    public double? ExpandedWidth { get; set; }
    public double? ExpandedHeight { get; set; }
    public AIConfiguration AI { get; set; } = new();
    public Dictionary<string, string> ManualTitles { get; set; } = new(StringComparer.Ordinal);
    public HashSet<string> ImportantSessionIds { get; set; } = new(StringComparer.Ordinal);
}

public sealed class AppStateStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter() }
    };

    private readonly object _lock = new();
    private readonly string _path;

    public AppStateStore(string? dataDirectory = null)
    {
        var directory = dataDirectory
            ?? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "AgentHUD");
        Directory.CreateDirectory(directory);
        _path = Path.Combine(directory, "settings.json");
        State = Load();
    }

    public PersistedAppState State { get; private set; }

    public void Save()
    {
        lock (_lock)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            var temporary = $"{_path}.tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(State, JsonOptions));
            File.Move(temporary, _path, true);
        }
    }

    public void SetManualTitle(string sessionId, string? title)
    {
        lock (_lock)
        {
            if (string.IsNullOrWhiteSpace(title))
            {
                State.ManualTitles.Remove(sessionId);
            }
            else
            {
                State.ManualTitles[sessionId] = title.Trim();
            }
        }
        Save();
    }

    public void ToggleImportant(string sessionId)
    {
        lock (_lock)
        {
            if (!State.ImportantSessionIds.Remove(sessionId))
            {
                State.ImportantSessionIds.Add(sessionId);
            }
        }
        Save();
    }

    public void SetImportant(string sessionId, bool important)
    {
        if (string.IsNullOrWhiteSpace(sessionId))
        {
            return;
        }

        lock (_lock)
        {
            if (important)
            {
                State.ImportantSessionIds.Add(sessionId);
            }
            else
            {
                State.ImportantSessionIds.Remove(sessionId);
            }
        }
        Save();
    }

    private PersistedAppState Load()
    {
        if (!File.Exists(_path))
        {
            return new PersistedAppState();
        }
        try
        {
            var state = JsonSerializer.Deserialize<PersistedAppState>(
                File.ReadAllText(_path),
                JsonOptions) ?? new PersistedAppState();
            state.ManualTitles = new Dictionary<string, string>(
                state.ManualTitles ?? new Dictionary<string, string>(),
                StringComparer.Ordinal);
            state.ImportantSessionIds = new HashSet<string>(
                state.ImportantSessionIds ?? new HashSet<string>(),
                StringComparer.Ordinal);
            state.AI ??= new AIConfiguration();
            return state;
        }
        catch (JsonException)
        {
            return new PersistedAppState();
        }
        catch (IOException)
        {
            return new PersistedAppState();
        }
    }
}
