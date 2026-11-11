using AgentHUD.Core;
using Microsoft.UI.Xaml;
using XamlApplication = Microsoft.UI.Xaml.Application;

namespace AgentHUD.Windows;

public partial class App : XamlApplication
{
    private Window? _window;

    public static AppStateStore StateStore { get; private set; } = null!;
    public static CredentialStore Credentials { get; private set; } = null!;

    public App()
    {
        try
        {
            InitializeComponent();
        }
        catch (Exception exception)
        {
            WriteStartupFailure(exception);
            throw;
        }

        UnhandledException += (_, args) =>
        {
            System.Diagnostics.Debug.WriteLine(args.Exception);
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        StateStore = new AppStateStore();
        Credentials = new CredentialStore();
        _window = new MainWindow();
        if (Environment.GetCommandLineArgs().Contains("--show", StringComparer.OrdinalIgnoreCase))
        {
            _window.Activate();
        }
        else
        {
            ((MainWindow)_window).StartInBackground();
        }
    }

    private static void WriteStartupFailure(Exception exception)
    {
        try
        {
            var directory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "AgentHUD");
            Directory.CreateDirectory(directory);
            File.WriteAllText(
                Path.Combine(directory, "startup-error.log"),
                $"{DateTimeOffset.Now:O}{Environment.NewLine}{exception}");
        }
        catch
        {
            // Preserve the original startup exception if diagnostics cannot be written.
        }
    }
}
