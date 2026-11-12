import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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
  bool _handling = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _port.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _finish(Future<LinkedDevice> Function() action) async {
    if (_handling) return;
    setState(() {
      _handling = true;
      _error = null;
    });
    try {
      final LinkedDevice device = await action();
      if (!mounted) return;
      await context.read<DeviceStore>().upsert(device);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _handling = false);
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
        body: TabBarView(
          children: [
            _buildScanner(),
            _buildManualForm(),
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    onDetect: (capture) {
                      if (_handling || capture.barcodes.isEmpty) return;
                      final String? raw = capture.barcodes.first.rawValue;
                      if (raw == null) return;
                      try {
                        final PairingOffer offer = PairingOffer.fromQr(raw);
                        if (offer.expiresAt.isBefore(DateTime.now())) {
                          throw const FormatException(
                            '配对码已过期，请在 Windows 上生成新配对码',
                          );
                        }
                        _finish(
                          () =>
                              _api.completeQr(offer, LinkApi.defaultDeviceName),
                        );
                      } catch (error) {
                        setState(() {
                          _handling = true;
                          _error = error.toString();
                        });
                        Future<void>.delayed(const Duration(seconds: 2), () {
                          if (mounted) setState(() => _handling = false);
                        });
                      }
                    },
                  ),
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(HudRadii.hero),
                        border: Border.all(
                          color: HudColors.working.withValues(alpha: 0.42),
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const IgnorePointer(
                    child: Center(
                      child: _ScanFrame(),
                    ),
                  ),
                ],
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
            child: _handling
                ? const Padding(
                    key: ValueKey<String>('handling'),
                    padding: EdgeInsets.symmetric(vertical: HudSpacing.md),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  )
                : const Text(
                    '对准 Windows 上的 AgentHUD 配对二维码',
                    key: ValueKey<String>('hint'),
                    textAlign: TextAlign.center,
                    style: HudText.caption,
                  ),
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

  Widget _buildManualForm() {
    return ListView(
      padding: const EdgeInsets.all(HudSpacing.xxl),
      children: [
        const _FieldLabel('电脑局域网地址'),
        const SizedBox(height: HudSpacing.md),
        TextField(
          controller: _address,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(hintText: '例如 192.168.1.5'),
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
