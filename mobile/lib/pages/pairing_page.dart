import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../device_store.dart';
import '../link_api.dart';
import '../models.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({super.key});

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final _api = LinkApi();
  final _address = TextEditingController();
  final _port = TextEditingController();
  final _code = TextEditingController();
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
      final device = await action();
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: MobileScanner(
              onDetect: (capture) {
                if (_handling || capture.barcodes.isEmpty) return;
                final raw = capture.barcodes.first.rawValue;
                if (raw == null) return;
                try {
                  final offer = PairingOffer.fromQr(raw);
                  if (offer.expiresAt.isBefore(DateTime.now())) {
                    throw const FormatException('配对码已过期，请在 Windows 上生成新配对码');
                  }
                  _finish(() => _api.completeQr(offer, LinkApi.defaultDeviceName));
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
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              if (_handling) const CircularProgressIndicator(),
              const SizedBox(height: 10),
              const Text('对准 Windows 上的 AgentHUD 配对二维码', textAlign: TextAlign.center),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Color(0xFFFF8A9A))),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildManualForm() {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Text('电脑局域网地址', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _address,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: '例如 192.168.1.5'),
        ),
        const SizedBox(height: 18),
        const Text('监听端口', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _port,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '以 Windows 配对页显示为准'),
        ),
        const SizedBox(height: 18),
        const Text('六位验证码', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(hintText: '123456', counterText: ''),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _handling ? null : () {
            final address = _address.text.trim();
            final port = int.tryParse(_port.text.trim());
            if (address.isEmpty || port == null || _code.text.trim().length != 6) {
              setState(() => _error = '请填写正确的地址、端口和六位验证码');
              return;
            }
            _finish(() => _api.completeCode(
                  address: address,
                  port: port,
                  code: _code.text.trim(),
                  deviceName: LinkApi.defaultDeviceName,
                ));
          },
          icon: _handling
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.link),
          label: Text(_handling ? '正在关联…' : '开始关联'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: Color(0xFFFF8A9A))),
        ],
        const SizedBox(height: 24),
        const Text(
          '验证码两分钟内有效，最多尝试五次。首次连接后，App 会固定电脑证书指纹，后续请求都需要独立设备令牌。',
          style: TextStyle(color: Color(0xFF9AA8BA), height: 1.5),
        ),
      ],
    );
  }
}
