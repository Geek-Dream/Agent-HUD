using AgentHUD.Core;
using XamlApplication = Microsoft.UI.Xaml.Application;

namespace AgentHUD.Windows;

public partial class App : XamlApplication
{
    private Window? _window;

    public static AppStateStore StateStore { get; private set; } = null!;
    public static CredentialStore Credentials { get; private set; } = null!;

    public App()
    {
        InitializeComponent();
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
        _window.Activate();
    }
}
