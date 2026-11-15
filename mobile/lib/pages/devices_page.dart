import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../device_store.dart';
import '../link_api.dart';
import '../models.dart';
import '../theme.dart';
import 'pairing_page.dart';
import 'sessions_page.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key, this.healthApi});

  /// 测试注入用：设备卡片的可达性探测实现。
  final DeviceHealthApi? healthApi;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeviceStore>();
    return Scaffold(
      body: HudScaffoldBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _DevicesHeader(),
              Expanded(
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
                            0,
                            HudSpacing.xl,
                            120,
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                HudSpacing.xs,
                                HudSpacing.md,
                                HudSpacing.xs,
                                HudSpacing.md,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '已关联电脑',
                                    style: HudText.overline,
                                  ),
                                  const SizedBox(width: HudSpacing.md),
                                  HudCountBadge(
                                    value: '${store.devices.length}',
                                  ),
                                  const Spacer(),
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: 12,
                                    color: HudColors.textTertiary
                                        .withValues(alpha: 0.8),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '局域网直连',
                                    style: HudText.caption.copyWith(
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            for (final LinkedDevice device in store.devices)
                              _DeviceCard(
                                device: device,
                                healthApi: healthApi,
                              ),
                            const SizedBox(height: HudSpacing.lg),
                            const _DevicesHint(),
                          ],
                        ),
                ),
              ),
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

class _DevicesHeader extends StatelessWidget {
  const _DevicesHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HudSpacing.xl,
        HudSpacing.lg,
        HudSpacing.xl,
        HudSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  HudColors.working.withValues(alpha: 0.22),
                  HudColors.working.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: HudColors.working.withValues(alpha: 0.28),
              ),
            ),
            child: const Icon(
              Icons.grid_view_rounded,
              size: 18,
              color: HudColors.working,
            ),
          ),
          const SizedBox(width: HudSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AgentHUD',
                  style: HudText.display.copyWith(
                    fontSize: 22,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '手机端监控台',
                  style: HudText.caption.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 电脑是否在线必须是真实探测的结果。
///
/// 之前这里是恒亮的绿点 + 「在线」文案，电脑关机、拔网线都照样显示在线，
/// 用户点进去才发现连不上。现在进页面先探一次，之后每 15 秒复探一次。
class _DeviceCard extends StatefulWidget {
  const _DeviceCard({required this.device, this.healthApi});

  final LinkedDevice device;

  /// 测试注入用；正式运行时由本卡片自己创建 LinkApi。
  final DeviceHealthApi? healthApi;

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

enum _HealthState { checking, online, offline }

class _DeviceCardState extends State<_DeviceCard> {
  static const Duration _probeInterval = Duration(seconds: 15);

  late final DeviceHealthApi _api;
  late final bool _ownsApi;
  Timer? _timer;
  _HealthState _health = _HealthState.checking;

  LinkedDevice get device => widget.device;

  @override
  void initState() {
    super.initState();
    _ownsApi = widget.healthApi == null;
    _api = widget.healthApi ?? LinkApi();
    unawaited(_probe());
    _timer = Timer.periodic(_probeInterval, (_) => unawaited(_probe()));
  }

  @override
  void didUpdateWidget(covariant _DeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      setState(() => _health = _HealthState.checking);
      unawaited(_probe());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_ownsApi) _api.close();
    super.dispose();
  }

  Future<void> _probe() async {
    final bool reachable = await _api.probe(device);
    if (!mounted) return;
    final _HealthState next =
        reachable ? _HealthState.online : _HealthState.offline;
    if (next != _health) setState(() => _health = next);
  }

  @override
  Widget build(BuildContext context) {
    final String address = device.addresses.isEmpty
        ? '未记录地址'
        : formatLinkAddress(device.addresses.first, device.port);
    return Padding(
      padding: const EdgeInsets.only(bottom: HudSpacing.md),
      child: HudEntrance(
        child: HudSurfaceCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SessionsPage(device: device),
            ),
          ),
          color: HudColors.surfaceRaised.withValues(alpha: 0.72),
          radius: 18,
          padding: const EdgeInsets.fromLTRB(16, 16, 6, 16),
          child: Row(
            children: [
              const _DeviceGlyph(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            device.instanceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HudText.title.copyWith(
                              fontSize: 16,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: HudSpacing.md),
                        _HealthBadge(state: _health),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HudText.mono.copyWith(
                        fontSize: 11,
                        color: HudColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '设备操作',
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  size: 20,
                  color: HudColors.textTertiary,
                ),
                color: HudColors.surfaceRaised,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HudRadii.control),
                  side: const BorderSide(color: HudColors.borderStrong),
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
              Padding(
                padding: const EdgeInsets.only(right: HudSpacing.md, left: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: HudColors.textTertiary.withValues(alpha: 0.45),
                ),
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

class _DevicesHint extends StatelessWidget {
  const _DevicesHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: HudColors.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HudColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _HintRow(
            icon: Icons.bolt_rounded,
            title: '实时进度',
            text: '查看每个会话当前在做什么，无需切回电脑。',
          ),
          _HintRow(
            icon: Icons.alt_route_rounded,
            title: '局域网直连',
            text: '数据只在手机与电脑之间传输，不经过云端。',
          ),
          _HintRow(
            icon: Icons.send_rounded,
            title: '远程下发',
            text: '在电脑授权后，可直接回复或下发文字任务。',
          ),
        ],
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  const _HintRow({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: HudColors.controlFill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: HudColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: HudText.label.copyWith(fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: HudText.caption.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
        color: HudColors.controlFill,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: HudColors.borderStrong),
      ),
      child: const Icon(
        Icons.desktop_windows_outlined,
        size: 20,
        color: HudColors.textSecondary,
      ),
    );
  }
}

/// 真实可达性徽标：探测中 / 在线 / 离线。
class _HealthBadge extends StatelessWidget {
  const _HealthBadge({required this.state});

  final _HealthState state;

  @override
  Widget build(BuildContext context) {
    final (Color color, String label) = switch (state) {
      _HealthState.checking => (HudColors.textTertiary, '检测中'),
      _HealthState.online => (HudColors.completed, '在线'),
      _HealthState.offline => (HudColors.failed, '连不上'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusDot(color: color, pulsing: state == _HealthState.online),
        const SizedBox(width: 6),
        Text(
          label,
          style: HudText.caption.copyWith(
            fontSize: 10.5,
            color: color.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, required this.pulsing});

  final Color color;
  final bool pulsing;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: HudMotion.pulse,
    );
    if (widget.pulsing) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant _StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing == oldWidget.pulsing) return;
    if (widget.pulsing) {
      _pulse.repeat();
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pulsing) {
      return SizedBox(
        width: 12,
        height: 12,
        child: Center(child: _dot(widget.color, 6)),
      );
    }
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
                  child: _dot(widget.color, 7),
                ),
              ),
              child!,
            ],
          );
        },
        child: _dot(widget.color, 6),
      ),
    );
  }

  static Widget _dot(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
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
