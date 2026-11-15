import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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

  bool _handling = false;
  bool _useIpv6 = false;
  int _mode = 0;
  String? _error;
  String? _scanNotice;
  String? _attemptText;
  String? _lanWarning;
  bool _needsManualRetry = false;
  String? _failedRaw;
  String? _lastRejectedRaw;
  DateTime? _lastRejectedAt;
  int _scannerAttempt = 0;
  bool _slowStart = false;
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
    setState(() {
      _scannerAttempt++;
      _slowStart = false;
      _handling = false;
      _error = null;
      _scanNotice = null;
      _attemptText = null;
      _lanWarning = null;
      _needsManualRetry = false;
      _failedRaw = null;
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
    // 同一个失败过的二维码不再自动重试（每次最多要等一轮超时），但换一张新码
    // 必须立刻可用，否则用户会以为扫码又「没反应」了。
    if (raw == _failedRaw) return;
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

    _checkLan(offer.addresses);
    _finish(
      () => _api.completeQr(
        offer,
        LinkApi.defaultDeviceName,
        onAttempt: _onAttempt,
      ),
      failedRaw: raw,
    );
  }

  void _onAttempt(String host, int port, int index, int total) {
    if (!mounted) return;
    setState(() =>
        _attemptText = '正在连接 ${formatLinkAddress(host, port)}（$index/$total）');
  }

  Future<void> _checkLan(List<String> targets) async {
    final String? warning = await _lanWarningFor(targets);
    if (!mounted || warning == null) return;
    setState(() => _lanWarning = warning);
  }

  /// 手机与电脑不在同一网段时，连接会一路超时到 60 秒左右；先算出来直接告诉用户，
  /// 比让他在「正在关联」里干等有用得多。只对 IPv4 做推断，IPv6 不做猜测。
  Future<String?> _lanWarningFor(List<String> targets) async {
    // 电脑会同时上报真实网卡和虚拟机/网桥地址。只要其中任意一个与手机同网段，
    // 就说明确实在同一个局域网；只比对第一个地址会产生误报。
    final List<String> targetIPv4 =
        targets.map(normalizeLinkAddress).where(_isIPv4Literal).toList();
    if (targetIPv4.isEmpty) return null;
    List<String> local;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      local = interfaces
          .expand((interface) => interface.addresses)
          .map((address) => address.address)
          .toList();
    } on Object {
      return null;
    }
    if (local.isEmpty) return null;
    // 组网地址（Tailscale 一类）不在同一局域网的假设范围内：它们能否连通
    // 取决于双方是否加入同一张私网，与 WiFi 无关。对这类地址做网段推断
    // 只会给出错误的「不在同一网段」提示。
    final List<String> lanTargets =
        targetIPv4.where((target) => !_isCarrierGradeNAT(target)).toList();
    if (lanTargets.isEmpty) return null;
    final bool same = lanTargets
        .any((target) => local.any((mine) => _sameSubnet(mine, target)));
    if (same) return null;
    return '手机地址 ${local.first} 与电脑地址 ${lanTargets.first} 不在同一网段，'
        '可能没有连同一个 WiFi。';
  }

  /// RFC 6598 的 `100.64.0.0/10`，Tailscale / ZeroTier 一类组网使用。
  ///
  /// `/10` 不是整字节边界：第二段落在 64–127 才属于该网段。
  static bool _isCarrierGradeNAT(String value) {
    final List<String> parts = value.split('.');
    if (parts.length != 4) return false;
    final int? first = int.tryParse(parts[0]);
    final int? second = int.tryParse(parts[1]);
    if (first == null || second == null) return false;
    return first == 100 && second >= 64 && second <= 127;
  }

  /// 只有真正的点分十进制 IPv4 才能做网段比较。
  ///
  /// 组网主机名（如 `my-mac.tailnet-xxx.ts.net`）同样由四段点分组成，按字符串
  /// 直接比较会被当成 IPv4，导致远程连接被误报成「不在同一网段」。
  static bool _isIPv4Literal(String value) {
    final List<String> parts = value.split('.');
    if (parts.length != 4) return false;
    for (final String part in parts) {
      if (part.isEmpty || part.length > 3) return false;
      final int? octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return false;
      if (part.length > 1 && part.startsWith('0')) return false;
    }
    return true;
  }

  static bool _sameSubnet(String left, String right) {
    final List<String> a = left.split('.');
    final List<String> b = right.split('.');
    if (a.length != 4 || b.length != 4) return false;
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
  }

  Future<void> _finish(
    Future<LinkedDevice> Function() action, {
    String? failedRaw,
  }) async {
    if (_handling) return;
    _noticeTimer?.cancel();
    _startupTimer?.cancel();
    setState(() {
      _handling = true;
      _error = null;
      _scanNotice = null;
      _attemptText = null;
    });
    try {
      final LinkedDevice device = await action();
      if (!mounted) return;
      await context.read<DeviceStore>().upsert(device);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      // 失败原因必须留在屏幕上，并记住这张二维码：否则它会一直躺在取景框里
      // 被反复重试（每次最长约 60 秒），用户只会看到「扫了半天没反应」。
      setState(() {
        _handling = false;
        _attemptText = null;
        _error = error.toString();
        _needsManualRetry = true;
        _failedRaw = failedRaw;
      });
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _attemptText = null;
      _lanWarning = null;
      _needsManualRetry = false;
      _failedRaw = null;
      _lastRejectedRaw = null;
      _lastRejectedAt = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: const Text('关联电脑'),
      ),
      body: HudScaffoldBackground(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HudSpacing.xl,
                  HudSpacing.sm,
                  HudSpacing.xl,
                  HudSpacing.xl,
                ),
                child: _ModeSwitch(
                  index: _mode,
                  onChanged: _handling
                      ? null
                      : (value) => setState(() {
                            _mode = value;
                            // 扫码页和验证码页各有一份提示位置，切页时清掉旧提示，
                            // 否则会看到上一次页面残留的错误。
                            _error = null;
                            _lanWarning = null;
                            _needsManualRetry = false;
                            _attemptText = null;
                          }),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: HudMotion.base,
                  switchInCurve: HudMotion.easeOut,
                  switchOutCurve: HudMotion.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: _mode == 0
                      ? KeyedSubtree(
                          key: const ValueKey<String>('scan'),
                          child: _buildScanner(),
                        )
                      : KeyedSubtree(
                          key: const ValueKey<String>('code'),
                          child: _buildManualForm(),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scannerStatus() {
    if (_handling) {
      return Column(
        key: const ValueKey<String>('handling'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: HudSpacing.md),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ),
          if (_attemptText != null)
            Text(
              _attemptText!,
              textAlign: TextAlign.center,
              style: HudText.caption,
            ),
        ],
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

  Widget _buildScanner() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              HudSpacing.xl,
              0,
              HudSpacing.xl,
              HudSpacing.xl,
            ),
            child: HudSurfaceCard(
              radius: HudRadii.hero,
              color: const Color(0xFF05060A),
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(HudRadii.hero),
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
                      overlayBuilder: (context, constraints) =>
                          const IgnorePointer(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _ScanVignette(),
                            Center(child: _ScanFrame()),
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
            HudSpacing.lg,
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
        _Ipv6Toggle(
          value: _useIpv6,
          enabled: !_handling,
          onChanged: (value) => setState(() => _useIpv6 = value),
        ),
        if (_lanWarning != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HudSpacing.xl,
              HudSpacing.md,
              HudSpacing.xl,
              0,
            ),
            child: _InlineNotice(message: _lanWarning!),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HudSpacing.xl,
              HudSpacing.md,
              HudSpacing.xl,
              HudSpacing.lg,
            ),
            child: _InlineError(message: _error!),
          ),
        if (_needsManualRetry)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HudSpacing.xl,
              0,
              HudSpacing.xl,
              HudSpacing.lg,
            ),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _retry,
                child: const Text('重新尝试'),
              ),
            ),
          ),
        const SizedBox(height: HudSpacing.lg),
      ],
    );
  }

  Widget _buildManualForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        HudSpacing.xl,
        0,
        HudSpacing.xl,
        HudSpacing.xxl,
      ),
      children: [
        HudSurfaceCard(
          padding: const EdgeInsets.fromLTRB(
            HudSpacing.xl,
            HudSpacing.lg,
            HudSpacing.xl,
            HudSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FieldLabel('电脑地址'),
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
                decoration: const InputDecoration(
                  hintText: '以 Windows 配对页显示为准',
                ),
              ),
              const SizedBox(height: HudSpacing.xl),
              const _FieldLabel('六位验证码'),
              const SizedBox(height: HudSpacing.md),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                maxLength: 6,
                style: HudText.mono.copyWith(
                  fontSize: 18,
                  letterSpacing: 6,
                  color: HudColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText: '000000',
                  counterText: '',
                ),
                onSubmitted: (_) => _submitManual(),
              ),
              const SizedBox(height: HudSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _handling ? null : _submitManual,
                  child: _handling
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: HudColors.textTertiary,
                          ),
                        )
                      : const Text('开始关联'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: HudSpacing.lg),
        _Ipv6Toggle(
          value: _useIpv6,
          enabled: !_handling,
          onChanged: (value) => setState(() => _useIpv6 = value),
        ),
        if (_lanWarning != null) ...[
          const SizedBox(height: HudSpacing.lg),
          _InlineNotice(message: _lanWarning!),
        ],
        if (_error != null) ...[
          const SizedBox(height: HudSpacing.lg),
          _InlineError(message: _error!),
        ],
        const SizedBox(height: HudSpacing.lg),
        Text(
          '验证码两分钟内有效，最多尝试五次。首次连接后，App 会固定电脑证书指纹，后续请求都需要独立设备令牌。',
          style: HudText.caption.copyWith(height: 1.6),
        ),
        const SizedBox(height: HudSpacing.lg),
        const _RemoteHintCard(),
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
    _checkLan([address]);
    _finish(
      () => _api.completeCode(
        address: address,
        port: port,
        code: _code.text.trim(),
        deviceName: LinkApi.defaultDeviceName,
        onAttempt: _onAttempt,
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

/// Dims everything outside the capture window so the preview reads as one
/// deliberate surface instead of a raw camera feed.
class _ScanVignette extends StatelessWidget {
  const _ScanVignette();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScanMaskPainter(
        window: _ScanFrame.size,
        radius: 22,
        outside: const Color(0xB807080C),
      ),
    );
  }
}

class _ScanMaskPainter extends CustomPainter {
  const _ScanMaskPainter({
    required this.window,
    required this.radius,
    required this.outside,
  });

  final double window;
  final double radius;
  final Color outside;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect cutout = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: window,
        height: window,
      ),
      Radius.circular(radius),
    );
    final Path mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(cutout);
    canvas.drawPath(mask, Paint()..color = outside);
  }

  @override
  bool shouldRepaint(covariant _ScanMaskPainter oldDelegate) =>
      oldDelegate.window != window ||
      oldDelegate.radius != radius ||
      oldDelegate.outside != outside;
}

/// Four hairline corner marks – no glow, no breathing animation.
class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  static const double size = 216;
  static const double _arm = 30;

  @override
  Widget build(BuildContext context) {
    final Color line = HudColors.textPrimary.withValues(alpha: 0.9);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerFramePainter(color: line, arm: _arm),
      ),
    );
  }
}

class _CornerFramePainter extends CustomPainter {
  const _CornerFramePainter({required this.color, required this.arm});

  final Color color;
  final double arm;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const double r = 14;
    final double w = size.width;
    final double h = size.height;

    // Four rounded corner arcs with short arms.
    final Path path = Path()
      ..moveTo(0, arm)
      ..lineTo(0, r)
      ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
      ..lineTo(arm, 0)
      ..moveTo(w - arm, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: const Radius.circular(r))
      ..lineTo(w, arm)
      ..moveTo(w, h - arm)
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: const Radius.circular(r))
      ..lineTo(w - arm, h)
      ..moveTo(arm, h)
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: const Radius.circular(r))
      ..lineTo(0, h - arm);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerFramePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.arm != arm;
}

/// Segmented control used instead of the Material TabBar.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: HudColors.controlFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HudColors.border),
      ),
      child: Row(
        children: [
          for (int i = 0; i < 2; i += 1)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onChanged == null ? null : () => onChanged!(i),
                child: AnimatedContainer(
                  duration: HudMotion.fast,
                  curve: HudMotion.easeOut,
                  decoration: BoxDecoration(
                    color:
                        index == i ? HudColors.textPrimary : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: Text(
                      i == 0 ? '扫码关联' : '验证码',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            index == i ? FontWeight.w600 : FontWeight.w500,
                        color: index == i
                            ? HudColors.background
                            : HudColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Quiet row toggle for the IPv6 preference.
class _Ipv6Toggle extends StatelessWidget {
  const _Ipv6Toggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HudSpacing.xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(HudRadii.card),
        onTap: enabled ? () => onChanged(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: HudSpacing.md,
            vertical: HudSpacing.md,
          ),
          child: Row(
            children: [
              Icon(
                Icons.lan_outlined,
                size: 16,
                color: value ? HudColors.working : HudColors.textTertiary,
              ),
              const SizedBox(width: HudSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '优先使用 IPv6 地址连接',
                      style: HudText.bodySecondary.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 1),
                    const Text(
                      '电脑上报了 IPv6 时先试 IPv6，没有就自动回退到 IPv4',
                      style: HudText.caption,
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 24,
                width: 40,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Switch(
                    value: value,
                    onChanged: enabled ? onChanged : null,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ),
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

/// 橙色提示：用于「可能不在同一局域网」这类需要用户自己动手排查的情况。
class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HudSpacing.lg,
        vertical: HudSpacing.md,
      ),
      decoration: BoxDecoration(
        color: HudColors.waiting.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(HudRadii.control),
        border: Border.all(color: HudColors.waiting.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 15,
            color: HudColors.waiting,
          ),
          const SizedBox(width: HudSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: HudText.caption.copyWith(color: HudColors.waiting),
            ),
          ),
        ],
      ),
    );
  }
}

/// 不在同一局域网时的引导：手机和电脑都要在同一个组网里才能远程连接。
class _RemoteHintCard extends StatelessWidget {
  const _RemoteHintCard();

  static const String _storeURL = 'market://details?id=com.tailscale.ipn';
  static const String _fallbackURL =
      'https://play.google.com/store/apps/details?id=com.tailscale.ipn';

  Future<void> _openStore() async {
    // 先试应用商店的深链，失败再退回网页版；两者都失败时静默忽略，
    // 用户仍可自己去商店搜 Tailscale。
    if (await launchUrl(Uri.parse(_storeURL),
        mode: LaunchMode.externalApplication)) {
      return;
    }
    await launchUrl(Uri.parse(_fallbackURL),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HudSpacing.lg,
        vertical: HudSpacing.md,
      ),
      decoration: BoxDecoration(
        color: HudColors.surface,
        borderRadius: BorderRadius.circular(HudRadii.card),
        border: Border.all(color: HudColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.public_rounded,
                size: 15,
                color: HudColors.textTertiary,
              ),
              const SizedBox(width: HudSpacing.sm),
              Text('不在同一个 WiFi？', style: HudText.bodySecondary),
            ],
          ),
          const SizedBox(height: HudSpacing.sm),
          Text(
            '手机和电脑都装好 Tailscale 并登录同一账号后，'
            '电脑的配对窗口会出现一个 100. 开头的远程地址，把它填到上面的「电脑地址」即可。',
            style: HudText.caption.copyWith(height: 1.6),
          ),
          const SizedBox(height: HudSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _openStore,
              icon: const Icon(Icons.download_rounded, size: 15),
              label: const Text('获取 Tailscale'),
              style: TextButton.styleFrom(
                foregroundColor: HudColors.working,
                padding: const EdgeInsets.symmetric(
                  horizontal: HudSpacing.md,
                  vertical: HudSpacing.xs,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
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
