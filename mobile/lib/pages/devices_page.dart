import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../device_store.dart';
import '../models.dart';
import '../theme.dart';
import 'pairing_page.dart';
import 'sessions_page.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeviceStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('AgentHUD')),
      body: HudScaffoldBackground(
        child: AnimatedSwitcher(
          duration: HudMotion.base,
          switchInCurve: HudMotion.easeOut,
          switchOutCurve: HudMotion.easeIn,
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: store.isEmpty
              ? const _EmptyDevices(key: ValueKey<String>('empty'))
              : ListView(
                  key: const ValueKey<String>('devices'),
                  padding: const EdgeInsets.fromLTRB(
                    HudSpacing.xl,
                    HudSpacing.md,
                    HudSpacing.xl,
                    120,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        HudSpacing.xs,
                        HudSpacing.sm,
                        HudSpacing.xs,
                        HudSpacing.lg,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '已关联电脑',
                                  style: HudText.display,
                                ),
                                const SizedBox(height: HudSpacing.xs),
                                Text(
                                  '${store.devices.length} 台设备 · 局域网直连监控',
                                  style: HudText.caption,
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.lock_outline_rounded,
                            size: 13,
                            color: HudColors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                    for (final LinkedDevice device in store.devices)
                      _DeviceCard(device: device),
                  ],
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PairingPage()),
        ),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('关联电脑'),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final LinkedDevice device;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HudSpacing.lg),
      child: HudEntrance(
        child: HudSurfaceCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SessionsPage(device: device),
            ),
          ),
          color: HudColors.surface.withValues(alpha: 0.82),
          padding: const EdgeInsets.fromLTRB(
            HudSpacing.xl,
            HudSpacing.xl,
            HudSpacing.md,
            HudSpacing.xl,
          ),
          child: Row(
            children: [
              const _DeviceGlyph(),
              const SizedBox(width: HudSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            device.instanceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HudText.title,
                          ),
                        ),
                        const SizedBox(width: HudSpacing.sm),
                        const _OnlineDot(),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      formatLinkAddress(device.addresses.first, device.port),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HudText.mono.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '设备操作',
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  size: 20,
                  color: HudColors.textTertiary,
                ),
                color: HudColors.surfaceRaised,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HudRadii.control),
                  side: const BorderSide(color: HudColors.border),
                ),
                onSelected: (value) {
                  if (value == 'remove') _confirmRemove(context);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'remove',
                    child: Text('移除这台电脑'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除这台电脑？'),
        content: const Text('手机会删除本机保存的设备令牌。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<DeviceStore>().remove(device.id);
    }
  }
}

class _DeviceGlyph extends StatelessWidget {
  const _DeviceGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: HudColors.controlFill,
        borderRadius: BorderRadius.circular(HudRadii.card),
        border: Border.all(color: HudColors.border),
      ),
      child: const Icon(
        Icons.desktop_windows_outlined,
        size: 21,
        color: HudColors.textSecondary,
      ),
    );
  }
}

class _OnlineDot extends StatefulWidget {
  const _OnlineDot();

  @override
  State<_OnlineDot> createState() => _OnlineDotState();
}

class _OnlineDotState extends State<_OnlineDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: HudMotion.pulse,
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final double t = _pulse.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t) * 0.25,
                child: Transform.scale(
                  scale: 1 + t * 0.9,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: HudColors.completed,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: HudColors.completed,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: HudEntrance(
        offset: const Offset(0, 0.02),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: HudColors.controlFill,
                  shape: BoxShape.circle,
                  border: Border.all(color: HudColors.border),
                ),
                child: const Icon(
                  Icons.phonelink_rounded,
                  size: 32,
                  color: HudColors.textSecondary,
                ),
              ),
              const SizedBox(height: HudSpacing.xxl),
              const Text('还没有关联电脑', style: HudText.display),
              const SizedBox(height: HudSpacing.md),
              const Text(
                '在 Windows 或 macOS AgentHUD 中打开“手机关联”，\n扫码或输入验证码即可开始监控。',
                textAlign: TextAlign.center,
                style: HudText.bodySecondary,
              ),
              const SizedBox(height: HudSpacing.xxl),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PairingPage()),
                ),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('立即关联'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
