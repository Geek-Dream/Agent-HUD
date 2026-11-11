using System.Runtime.InteropServices;

namespace AgentHUD.Windows.Services;

internal sealed class TrayIcon : IDisposable
{
    private const uint NimAdd = 0x00000000;
    private const uint NimDelete = 0x00000002;
    private const uint NifMessage = 0x00000001;
    private const uint NifIcon = 0x00000002;
    private const uint NifTip = 0x00000004;
    private const uint MfString = 0x00000000;
    private const uint MfChecked = 0x00000008;
    private const uint MfSeparator = 0x00000800;
    private const uint TpmRightButton = 0x00000002;
    private const uint TpmReturnCommand = 0x00000100;
    private const int WmNull = 0x0000;
    private const int WmContextMenu = 0x007B;
    private const int WmApp = 0x8000;
    private const int TrayCallbackMessage = WmApp + 1;
    private const int WmLeftButtonDoubleClick = 0x0203;
    private const int WmRightButtonUp = 0x0205;
    private const int IdiApplication = 32512;
    private const uint ImageIcon = 1;
    private const uint LrLoadFromFile = 0x00000010;
    private const uint LrDefaultSize = 0x00000040;

    private const uint ShowCommand = 1;
    private const uint ExpandCommand = 2;
    private const uint RefreshCommand = 3;
    private const uint PrivacyCommand = 4;
    private const uint LockCommand = 5;
    private const uint SettingsCommand = 6;
    private const uint ExitCommand = 7;
    private const uint LinkCommand = 8;

    private readonly IntPtr _windowHandle;
    private readonly Action _toggleVisibility;
    private readonly Action _toggleExpanded;
    private readonly Action _refresh;
    private readonly Action _togglePrivacy;
    private readonly Action _togglePositionLock;
    private readonly Action _openSettings;
    private readonly Action _openLinkSettings;
    private readonly Action _exit;
    private readonly Func<bool> _isVisible;
    private readonly Func<bool> _isExpanded;
    private readonly Func<bool> _isPrivacyMode;
    private readonly Func<bool> _isPositionLocked;
    private readonly SubclassProc _subclassProc;
    private readonly IntPtr _icon;
    private bool _ownsIcon;
    private bool _disposed;

    public TrayIcon(
        IntPtr windowHandle,
        Action toggleVisibility,
        Action toggleExpanded,
        Action refresh,
        Action togglePrivacy,
        Action togglePositionLock,
        Action openSettings,
        Action openLinkSettings,
        Action exit,
        Func<bool> isVisible,
        Func<bool> isExpanded,
        Func<bool> isPrivacyMode,
        Func<bool> isPositionLocked)
    {
        _windowHandle = windowHandle;
        _toggleVisibility = toggleVisibility;
        _toggleExpanded = toggleExpanded;
        _refresh = refresh;
        _togglePrivacy = togglePrivacy;
        _togglePositionLock = togglePositionLock;
        _openSettings = openSettings;
        _openLinkSettings = openLinkSettings;
        _exit = exit;
        _isVisible = isVisible;
        _isExpanded = isExpanded;
        _isPrivacyMode = isPrivacyMode;
        _isPositionLocked = isPositionLocked;
        _subclassProc = WindowSubclassProc;
        _icon = LoadTrayIcon();

        if (!SetWindowSubclass(_windowHandle, _subclassProc, UIntPtr.Zero, IntPtr.Zero))
        {
            throw new InvalidOperationException("Unable to install the AgentHUD tray message handler.");
        }

        var data = CreateIconData();
        if (!ShellNotifyIcon(NimAdd, ref data))
        {
            RemoveWindowSubclass(_windowHandle, _subclassProc, UIntPtr.Zero);
            throw new InvalidOperationException("Unable to create the AgentHUD tray icon.");
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        var data = CreateIconData();
        ShellNotifyIcon(NimDelete, ref data);
        RemoveWindowSubclass(_windowHandle, _subclassProc, UIntPtr.Zero);
        if (_ownsIcon)
        {
            DestroyIcon(_icon);
        }
    }

    private IntPtr LoadTrayIcon()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Assets", "AgentHUD.ico");
        if (File.Exists(path))
        {
            var icon = LoadImage(
                IntPtr.Zero,
                path,
                ImageIcon,
                0,
                0,
                LrLoadFromFile | LrDefaultSize);
            if (icon != IntPtr.Zero)
            {
                _ownsIcon = true;
                return icon;
            }
        }

        return LoadIcon(IntPtr.Zero, (IntPtr)IdiApplication);
    }

    private NotifyIconData CreateIconData() => new()
    {
        Size = Marshal.SizeOf<NotifyIconData>(),
        WindowHandle = _windowHandle,
        Id = 1,
        Flags = NifMessage | NifIcon | NifTip,
        CallbackMessage = TrayCallbackMessage,
        Icon = _icon,
        Tip = "AgentHUD",
        Info = string.Empty,
        InfoTitle = string.Empty
    };

    private IntPtr WindowSubclassProc(
        IntPtr hWnd,
        uint message,
        IntPtr wParam,
        IntPtr lParam,
        UIntPtr subclassId,
        IntPtr refData)
    {
        if (message == TrayCallbackMessage)
        {
            var trayEvent = (int)(lParam.ToInt64() & 0xFFFF);
            if (trayEvent == WmLeftButtonDoubleClick)
            {
                _toggleVisibility();
                return IntPtr.Zero;
            }

            if (trayEvent is WmRightButtonUp or WmContextMenu)
            {
                ShowMenu();
                return IntPtr.Zero;
            }
        }

        return DefSubclassProc(hWnd, message, wParam, lParam);
    }

    private void ShowMenu()
    {
        var menu = CreatePopupMenu();
        if (menu == IntPtr.Zero)
        {
            return;
        }

        try
        {
            AppendMenu(menu, MfString, ShowCommand, _isVisible() ? "隐藏 AgentHUD" : "显示 AgentHUD");
            AppendMenu(menu, MfString, ExpandCommand, _isExpanded() ? "收起面板" : "展开面板");
            AppendMenu(menu, MfSeparator, 0, null);
            AppendMenu(menu, MfString, RefreshCommand, "立即刷新");
            AppendMenu(
                menu,
                MfString | (_isPrivacyMode() ? MfChecked : 0),
                PrivacyCommand,
                "隐私模式");
            AppendMenu(
                menu,
                MfString | (_isPositionLocked() ? MfChecked : 0),
                LockCommand,
                "锁定位置");
            AppendMenu(menu, MfString, LinkCommand, "手机关联...");
            AppendMenu(menu, MfString, SettingsCommand, "AI 标题设置...");
            AppendMenu(menu, MfSeparator, 0, null);
            AppendMenu(menu, MfString, ExitCommand, "退出 AgentHUD");

            GetCursorPos(out var cursor);
            SetForegroundWindow(_windowHandle);
            var command = TrackPopupMenuEx(
                menu,
                TpmRightButton | TpmReturnCommand,
                cursor.X,
                cursor.Y,
                _windowHandle,
                IntPtr.Zero);
            PostMessage(_windowHandle, WmNull, IntPtr.Zero, IntPtr.Zero);
            InvokeCommand(command);
        }
        finally
        {
            DestroyMenu(menu);
        }
    }

    private void InvokeCommand(uint command)
    {
        switch (command)
        {
            case ShowCommand:
                _toggleVisibility();
                break;
            case ExpandCommand:
                _toggleExpanded();
                break;
            case RefreshCommand:
                _refresh();
                break;
            case PrivacyCommand:
                _togglePrivacy();
                break;
            case LockCommand:
                _togglePositionLock();
                break;
            case SettingsCommand:
                _openSettings();
                break;
            case LinkCommand:
                _openLinkSettings();
                break;
            case ExitCommand:
                _exit();
                break;
        }
    }

    private static bool AppendMenu(IntPtr menu, uint flags, uint command, string? text) =>
        AppendMenuNative(menu, flags, (UIntPtr)command, text);

    private delegate IntPtr SubclassProc(
        IntPtr hWnd,
        uint message,
        IntPtr wParam,
        IntPtr lParam,
        UIntPtr subclassId,
        IntPtr refData);

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyIconData
    {
        public int Size;
        public IntPtr WindowHandle;
        public uint Id;
        public uint Flags;
        public uint CallbackMessage;
        public IntPtr Icon;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string Tip;

        public uint State;
        public uint StateMask;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string Info;

        public uint Version;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string InfoTitle;

        public uint InfoFlags;
        public Guid ItemGuid;
        public IntPtr BalloonIcon;
    }

    [DllImport("shell32.dll", EntryPoint = "Shell_NotifyIconW", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShellNotifyIcon(uint message, ref NotifyIconData data);

    [DllImport("comctl32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowSubclass(
        IntPtr hWnd,
        SubclassProc subclassProc,
        UIntPtr subclassId,
        IntPtr refData);

    [DllImport("comctl32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RemoveWindowSubclass(
        IntPtr hWnd,
        SubclassProc subclassProc,
        UIntPtr subclassId);

    [DllImport("comctl32.dll")]
    private static extern IntPtr DefSubclassProc(
        IntPtr hWnd,
        uint message,
        IntPtr wParam,
        IntPtr lParam);

    [DllImport("user32.dll", EntryPoint = "LoadIconW")]
    private static extern IntPtr LoadIcon(IntPtr instance, IntPtr iconName);

    [DllImport("user32.dll", EntryPoint = "LoadImageW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadImage(
        IntPtr instance,
        string name,
        uint type,
        int width,
        int height,
        uint flags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr icon);

    [DllImport("user32.dll")]
    private static extern IntPtr CreatePopupMenu();

    [DllImport("user32.dll", EntryPoint = "AppendMenuW", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AppendMenuNative(
        IntPtr menu,
        uint flags,
        UIntPtr command,
        string? text);

    [DllImport("user32.dll")]
    private static extern uint TrackPopupMenuEx(
        IntPtr menu,
        uint flags,
        int x,
        int y,
        IntPtr owner,
        IntPtr parameters);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyMenu(IntPtr menu);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out Point point);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll", EntryPoint = "PostMessageW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostMessage(
        IntPtr hWnd,
        int message,
        IntPtr wParam,
        IntPtr lParam);
}
