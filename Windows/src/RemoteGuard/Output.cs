namespace RemoteGuard;

/// <summary>
/// 输出汇聚。程序是 WinExe（不弹黑壳），结果统一写入调用方指定的文件。
///
/// 编码约定（踩过两轮坑，这里是最终结论）：
///   · **一律按系统 ANSI（中文 Windows = CP936/GBK）写，无 BOM**。
///   · 原因：cmd.exe 解析批处理文件时按 ANSI 读字节，与 chcp 无关。
///     BAT 若含中文就必须存 GBK，控制台保持 936，那么 type 显示的结果文件
///     也必须是 GBK，三者才一致。
///   · 之前试过 UTF-8 + chcp 65001，反而让 BAT 中文行被按 GBK 截断，
///     把 "[2] 取消远程办公模式" 解析成了一条要执行的命令。
///   · 机器可读输出（--mode）只用 ASCII，BAT 因此不需要解析任何中文。
/// </summary>
public sealed class Output
{
    /// <summary>中文 Windows 的 ANSI 代码页，与 cmd.exe 解析批处理的编码一致。</summary>
    private const int AnsiCodePage = 936;

    private static readonly System.Text.Encoding AnsiEncoding = CreateAnsi();

    private static System.Text.Encoding CreateAnsi()
    {
        // .NET 8 默认不注册代码页提供程序，需要显式注册才能拿到 GBK
        System.Text.Encoding.RegisterProvider(System.Text.CodePagesEncodingProvider.Instance);
        try
        {
            return System.Text.Encoding.GetEncoding(AnsiCodePage,
                new System.Text.EncoderReplacementFallback("?"),
                new System.Text.DecoderReplacementFallback("?"));
        }
        catch
        {
            return System.Text.Encoding.Default;
        }
    }

    private readonly List<string> _lines = new();
    private readonly string? _filePath;

    public Output(string? filePath) => _filePath = filePath;

    public void Write(string message)
    {
        _lines.Add(message);
        if (_filePath is null)
        {
            try { Console.WriteLine(message); } catch { }
        }
    }

    public void WriteBlank() => Write(string.Empty);

    /// <summary>落盘。GBK 无 BOM，保证 BAT 的 type 能原样显示。</summary>
    public void Flush()
    {
        if (_filePath is null) return;
        try
        {
            var dir = Path.GetDirectoryName(_filePath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(_filePath, string.Join(Environment.NewLine, _lines), AnsiEncoding);
        }
        catch { }
    }
}