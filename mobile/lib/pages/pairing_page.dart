import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../device_store.dart';
import '../link_api.dart';
import '../models.dart';
import '../theme.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({super.key});

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final LinkApi _api = LinkApi();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _port = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final GlobalKey _scannerKey = GlobalKey();

  bool _handling = false;
  bool _useIpv6 = false;
  String? _error;
  String? _scanNotice;
  String? _lastRejectedRaw;
  DateTime? _lastRejectedAt;
  int _scannerAttempt = 0;
  bool _slowStart = false;
  String? _capturedPath;
  Timer? _startupTimer;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    _armStartupTimer();
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    _noticeTimer?.cancel();
    _address.dispose();
    _port.dispose();
    _code.dispose();
    _deleteCapturedFile();
    super.dispose();
  }

  void _armStartupTimer() {
    _startupTimer?.cancel();
    _startupTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _slowStart = true);
    });
  }

  void _restartScanner() {
    _startupTimer?.cancel();
    _noticeTimer?.cancel();
    _deleteCapturedFile();
    setState(() {
      _scannerAttempt++;
      _slowStart = false;
      _handling = false;
      _error = null;
      _scanNotice = null;
      _lastRejectedRaw = null;
      _lastRejectedAt = null;
    });
    _armStartupTimer();
  }

  void _showScanNotice(String message) {
    _noticeTimer?.cancel();
    setState(() => _scanNotice = message);
    _noticeTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _scanNotice = null);
    });
  }

  /// Capture a screenshot of the scanner preview and save to temp directory.
  Future<void> _captureScreenshot() async {
    try {
      final RenderObject? renderObject =
          _scannerKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) return;

      final ui.Image image = await renderObject.toImage(pixelRatio: 2.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) return;

      final Directory tempDir = await getTemporaryDirectory();
      final String path =
          '${tempDir.path}/agent_hud_scan_${DateTime.now().millisecondsSinceEpoch}.png';
      final File file = File(path);
      await file.writeAsBytes(byteData.buffer.asUint8List());

      if (mounted) setState(() => _capturedPath = path);
    } catch (_) {
      // Screenshot is best-effort; do not block pairing on failure.
    }
  }

  /// Delete the captured screenshot file if it exists.
  void _deleteCapturedFile() {
    final String? path = _capturedPath;
    if (path == null) return;
    _capturedPath = null;
    try {
      File(path).deleteSync();
    } catch (_) {
      // Ignore cleanup errors.
    }
  }

  void _onScan(BarcodeCapture capture) {
    if (!mounted || _handling) return;
    Barcode? barcode;
    for (final candidate in capture.barcodes) {
      if (candidate.format == BarcodeFormat.qrCode &&
          candidate.rawValue != null) {
        barcode = candidate;
        break;
      }
    }
    if (barcode == null) return;

    _startupTimer?.cancel();
    final String raw = barcode.rawValue!;
    final DateTime now = DateTime.now();
    final DateTime? rejectedAt = _lastRejectedAt;
    if (raw == _lastRejectedRaw &&
        rejectedAt != null &&
        now.difference(rejectedAt) < const Duration(seconds: 3)) {
      return;
    }

    PairingOffer offer;
    try {
      offer = PairingOffer.fromQr(raw, preferIpv6: _useIpv6);
    } on FormatException catch (error) {
      // 把真实原因（例如勾选 IPv6 但没有可用 IPv6 地址）告诉用户，
      // 否则一律显示「不是 AgentHUD 的二维码」，排查时会被误导。
      _lastRejectedRaw = raw;
      _lastRejectedAt = now;
      _showScanNotice(error.message);
      return;
    } catch (_) {
      _lastRejectedRaw = raw;
      _lastRejectedAt = now;
      _showScanNotice('这不是 AgentHUD 的配对二维码');
      return;
    }
    if (offer.expiresAt.isBefore(now)) {
      _lastRejectedRaw = raw;
      _lastRejectedAt = now;
      _showScanNotice('配对码已过期，请在电脑上生成新配对码');
      return;
    }

    // Freeze the UI by capturing a screenshot and entering handling state.
    _captureScreenshot();
    _finish(
      () => _api.completeQr(
        offer,
        LinkApi.defaultDeviceName,
        preferIpv6: _useIpv6,
      ),
    );
  }

  Future<void> _finish(Future<LinkedDevice> Function() action) async {
    if (_handling) return;
    _noticeTimer?.cancel();
    _startupTimer?.cancel();
    setState(() {
      _handling = true;
      _error = null;
      _scanNotice = null;
    });
    try {
      final LinkedDevice device = await action();
      _deleteCapturedFile();
      if (!mounted) return;
      await context.read<DeviceStore>().upsert(device);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      _deleteCapturedFile();
      if (!mounted) return;
      setState(() => _error = error.toString());
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() {
          _handling = false;
          _error = null;
        });
        _armStartupTimer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('关联电脑'),
          bottom: const TabBar(tabs: [Tab(text: '扫码关联'), Tab(text: '验证码')]),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HudSpacing.xxl,
                HudSpacing.md,
                HudSpacing.xxl,
                0,
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: _useIpv6,
                    onChanged: _handling
                        ? null
                        : (value) => setState(
                              () => _useIpv6 = value ?? false,
                            ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _handling
                          ? null
                          : () => setState(() => _useIpv6 = !_useIpv6),
                      child: Text(
                        '仅使用 IPv6 地址连接',
                        style: HudText.bodySecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildScanner(),
                  _buildManualForm(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanner() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(HudSpacing.xl),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(HudRadii.hero),
              child: RepaintBoundary(
                key: _scannerKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      key: ValueKey<int>(_scannerAttempt),
                      onDetect: _onScan,
                      tapToFocus: true,
                      errorBuilder: (context, error) => _CameraError(
                        error: error,
                        onRetry: _restartScanner,
                      ),
                      placeholderBuilder: (context) => _CameraStarting(
                        slow: _slowStart,
                        onRetry: _restartScanner,
                      ),
                      overlayBuilder: (context, constraints) => IgnorePointer(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(HudRadii.hero),
                                border: Border.all(
                                  color: HudColors.working
                                      .withValues(alpha: 0.42),
                                  width: 1.2,
                                ),
                              ),
                            ),
                            const Center(child: _ScanFrame()),
                          ],
                        ),
                      ),
                    ),
                    if (_handling) _CaptureOverlay(),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HudSpacing.xxl,
            0,
            HudSpacing.xxl,
            HudSpacing.xxl,
          ),
          child: AnimatedSwitcher(
            duration: HudMotion.base,
            switchInCurve: HudMotion.easeOut,
            switchOutCurve: HudMotion.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
            child: _scannerStatus(),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HudSpacing.xxl,
              0,
              HudSpacing.xxl,
              HudSpacing.xxl,
            ),
            child: _InlineError(message: _error!),
          ),
      ],
    );
  }

  Widget _scannerStatus() {
    if (_handling) {
      return const Padding(
        key: ValueKey<String>('handling'),
        padding: EdgeInsets.symmetric(vertical: HudSpacing.md),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    if (_scanNotice != null) {
      return Text(
        _scanNotice!,
        key: const ValueKey<String>('notice'),
        textAlign: TextAlign.center,
        style: HudText.caption.copyWith(color: HudColors.waiting),
      );
    }
    return const Text(
      '对准电脑上的 AgentHUD 配对二维码',
      key: ValueKey<String>('hint'),
      textAlign: TextAlign.center,
      style: HudText.caption,
    );
  }

  Widget _buildManualForm() {
    return ListView(
      padding: const EdgeInsets.all(HudSpacing.xxl),
      children: [
        _FieldLabel(_useIpv6 ? '电脑地址（IPv6）' : '电脑地址（IPv4 或 IPv6）'),
        const SizedBox(height: HudSpacing.md),
        TextField(
          controller: _address,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: _useIpv6
                ? '2409:…（无需方括号）'
                : '192.168.1.5 或 2409:…（无需方括号）',
          ),
        ),
        const SizedBox(height: HudSpacing.xl),
        const _FieldLabel('监听端口'),
        const SizedBox(height: HudSpacing.md),
        TextField(
          controller: _port,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(hintText: '以 Windows 配对页显示为准'),
        ),
        const SizedBox(height: HudSpacing.xl),
        const _FieldLabel('六位验证码'),
        const SizedBox(height: HudSpacing.md),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          maxLength: 6,
          decoration: const InputDecoration(
            hintText: '123456',
            counterText: '',
          ),
          onSubmitted: (_) => _submitManual(),
        ),
        const SizedBox(height: HudSpacing.lg),
        FilledButton.icon(
          onPressed: _handling ? null : _submitManual,
          icon: _handling
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF04121F),
                  ),
                )
              : const Icon(Icons.link_rounded, size: 19),
          label: Text(_handling ? '正在关联…' : '开始关联'),
        ),
        if (_error != null) ...[
          const SizedBox(height: HudSpacing.lg),
          _InlineError(message: _error!),
        ],
        const SizedBox(height: HudSpacing.xxl),
        const Text(
          '验证码两分钟内有效，最多尝试五次。首次连接后，App 会固定电脑证书指纹，后续请求都需要独立设备令牌。',
          style: HudText.caption,
        ),
      ],
    );
  }

  void _submitManual() {
    final String address = _address.text.trim();
    final int? port = int.tryParse(_port.text.trim());
    if (address.isEmpty || port == null || _code.text.trim().length != 6) {
      setState(() => _error = '请填写正确的地址、端口和六位验证码');
      return;
    }
    _finish(
      () => _api.completeCode(
        address: address,
        port: port,
        code: _code.text.trim(),
        deviceName: LinkApi.defaultDeviceName,
      ),
    );
  }
}

/// Dark overlay shown on top of the scanner when a code has been captured
/// and pairing is in progress. Prevents the user from "waving around".
class _CaptureOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: HudColors.working,
              ),
            ),
            SizedBox(height: HudSpacing.lg),
            Text(
              '已识别二维码，正在关联…',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: HudColors.textPrimary,
              ),
            ),
            SizedBox(height: HudSpacing.sm),
            Text(
              '请保持手机稳定',
              style: TextStyle(
                fontSize: 11.5,
                color: HudColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error, required this.onRetry});

  final MobileScannerException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final bool permissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    final bool unsupported =
        error.errorCode == MobileScannerErrorCode.unsupported;
    final String title = permissionDenied
        ? '需要相机权限'
        : unsupported
            ? '无法使用扫码'
            : '相机启动失败';
    final String message = permissionDenied
        ? '请在系统设置中允许 AgentHUD 使用相机，然后返回重试。'
        : unsupported
            ? '当前设备不支持相机扫码，请改用"验证码"关联。'
            : '请关闭其他正在使用相机的应用，然后重试。';
    final String? detail = error.errorDetails?.message;

    return ColoredBox(
      color: HudColors.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(HudSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                permissionDenied
                    ? Icons.no_photography_outlined
                    : Icons.videocam_off_outlined,
                size: 30,
                color: HudColors.textTertiary,
              ),
              const SizedBox(height: HudSpacing.lg),
              Text(title, style: HudText.title),
              const SizedBox(height: HudSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: HudText.bodySecondary,
              ),
              if (detail != null && detail.isNotEmpty) ...[
                const SizedBox(height: HudSpacing.sm),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: HudText.caption,
                ),
              ],
              const SizedBox(height: HudSpacing.lg),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraStarting extends StatelessWidget {
  const _CameraStarting({required this.slow, required this.onRetry});

  final bool slow;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: HudColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (slow) ...[
              const Icon(
                Icons.hourglass_empty_rounded,
                size: 28,
                color: HudColors.textTertiary,
              ),
              const SizedBox(height: HudSpacing.lg),
              const Text('相机启动较慢', style: HudText.caption),
              const SizedBox(height: HudSpacing.sm),
              TextButton(onPressed: onRetry, child: const Text('重新启动')),
            ] else ...[
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(height: HudSpacing.lg),
              const Text('正在启动相机…', style: HudText.caption),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 196,
      height: 196,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HudRadii.hero),
        border: Border.all(
          color: HudColors.working.withValues(alpha: 0.72),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: HudColors.working.withValues(alpha: 0.22),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: HudText.label);
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HudSpacing.lg,
        vertical: HudSpacing.md,
      ),
      decoration: BoxDecoration(
        color: HudColors.failed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(HudRadii.control),
        border: Border.all(color: HudColors.failed.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 15,
            color: HudColors.failed,
          ),
          const SizedBox(width: HudSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: HudText.caption.copyWith(color: HudColors.failed),
            ),
          ),
        ],
      ),
    );
  }
}
