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
      body: AnimatedSwitcher(
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
                  100,
                ),
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: HudSpacing.lg),
                    child: Row(
                      children: [
                        const Text('已关联电脑', style: HudText.title),
                        const SizedBox(width: HudSpacing.md),
                        _CountBadge(count: store.devices.length),
                        const Spacer(),
                        const Icon(
                          Icons.lock_outline_rounded,
                          size: 14,
                          color: HudColors.textTertiary,
                        ),
                        const SizedBox(width: HudSpacing.xs),
                        const Text('只读监控', style: HudText.caption),
                      ],
                    ),
                  ),
                  for (final LinkedDevice device in store.devices)
                    _DeviceCard(device: device),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PairingPage()),
        ),
        icon: const Icon(Icons.add_link_rounded),
        label: const Text('关联电脑'),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: HudColors.controlFill,
        borderRadius: BorderRadius.circular(HudRadii.micro),
        border: Border.all(color: HudColors.border),
      ),
      child: Text(
        '$count',
        style: HudText.micro.copyWith(color: HudColors.textSecondary),
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
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [HudColors.surfaceRaised, HudColors.surface],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(HudRadii.hero),
              border: Border.all(color: HudColors.border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(HudRadii.hero),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SessionsPage(device: device),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  HudSpacing.xl,
                  HudSpacing.xl,
                  HudSpacing.md,
                  HudSpacing.xl,
                ),
                child: Row(
                  children: [
                    const _DeviceGlyph(),
                    const SizedBox(width: HudSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.instanceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HudText.title.copyWith(fontSize: 15.5),
                          ),
                          const SizedBox(height: HudSpacing.xs),
                          Text(
                            formatLinkAddress(
                                device.addresses.first, device.port),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HudText.caption.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '移除设备',
                      iconSize: 19,
                      color: HudColors.textTertiary,
                      onPressed: () => _confirmRemove(context),
                      icon: const Icon(Icons.link_off_rounded),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: HudColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HudColors.surfaceRaised,
        title: const Text('移除这台电脑？', style: HudText.title),
        content: const Text('手机会删除本机保存的设备令牌。', style: HudText.bodySecondary),
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
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            HudColors.working.withValues(alpha: 0.24),
            HudColors.working.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(HudRadii.card),
        border: Border.all(color: HudColors.working.withValues(alpha: 0.32)),
      ),
      child: const Icon(
        Icons.desktop_windows_rounded,
        size: 21,
        color: HudColors.working,
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
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      HudColors.working.withValues(alpha: 0.26),
                      HudColors.working.withValues(alpha: 0.04),
                    ],
                  ),
                  border: Border.all(
                    color: HudColors.working.withValues(alpha: 0.28),
                  ),
                ),
                child: const Icon(
                  Icons.devices_other_rounded,
                  size: 36,
                  color: HudColors.working,
                ),
              ),
              const SizedBox(height: HudSpacing.xxl),
              const Text('还没有关联电脑', style: HudText.display),
              const SizedBox(height: HudSpacing.md),
              const Text(
                '在 Windows AgentHUD 中打开“手机关联”，使用手机扫码或输入验证码即可开始只读监控。',
                textAlign: TextAlign.center,
                style: HudText.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
