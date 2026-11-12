import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../session_controller.dart';
import '../theme.dart';
import '../widgets/hud_chips.dart';
import 'session_detail_page.dart';

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key, required this.device});

  final LinkedDevice device;

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final SessionController _controller;
  late final AnimationController _pulse;
  late final AnimationController _entrance;

  bool _reduceMotion = false;
  bool _entrancePlayed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(vsync: this, duration: HudMotion.pulse);
    _entrance = AnimationController(
      vsync: this,
      duration: HudMotion.entrance,
    );
    _controller = SessionController(widget.device);
    _controller.addListener(_changed);
    _controller.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduce = HudMotion.reduced(context);
    if (reduce == _reduceMotion) return;
    _reduceMotion = reduce;
    if (reduce) {
      _entrance.value = 1;
      _pulse.stop();
      _pulse.value = 0;
    } else {
      _syncPulse();
    }
  }

  void _changed() {
    if (!mounted) return;
    final bool firstData = !_entrancePlayed && _controller.sessions.isNotEmpty;
    setState(() {});
    _syncPulse();
    if (firstData) {
      _entrancePlayed = true;
      if (_reduceMotion) {
        _entrance.value = 1;
      } else {
        _entrance.forward(from: 0);
      }
    }
  }

  void _syncPulse() {
    if (!mounted) return;
    final bool active = _controller.sessions
        .any((session) => HudColors.isActive(session.status));
    final bool loading = _controller.isRefreshing &&
        _controller.lastUpdated == null &&
        _controller.sessions.isEmpty;
    if ((active || loading) && !_reduceMotion) {
      if (!_pulse.isAnimating) {
        _pulse.repeat(reverse: true);
      }
    } else if (_pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_changed)
      ..dispose();
    _pulse.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SessionController controller = _controller;
    final List<AgentSession> sessions = controller.sessions;
    final bool showSkeleton = sessions.isEmpty &&
        controller.lastUpdated == null &&
        controller.isRefreshing;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.instanceName),
        actions: [
          if (controller.status?.privacyMode == true)
            const Tooltip(
              message: '隐私模式已开启',
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: HudSpacing.md),
                child: Icon(
                  Icons.visibility_off_outlined,
                  size: 19,
                  color: HudColors.waiting,
                ),
              ),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: controller.refresh,
            icon: const Icon(Icons.refresh_rounded, size: 21),
          ),
          const SizedBox(width: HudSpacing.xs),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [HudColors.background, HudColors.window],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            _Filters(controller: controller),
            _ErrorBanner(message: controller.error),
            Expanded(
              child: RefreshIndicator(
                color: HudColors.working,
                backgroundColor: HudColors.surfaceRaised,
                onRefresh: controller.refresh,
                child: AnimatedSwitcher(
                  duration: HudMotion.base,
                  switchInCurve: HudMotion.easeOut,
                  switchOutCurve: HudMotion.easeIn,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.012),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: showSkeleton
                      ? _SkeletonList(
                          key: const ValueKey<String>('skeleton'),
                          pulse: _pulse,
                        )
                      : sessions.isEmpty
                          ? _EmptyList(
                              key: ValueKey<String>(
                                'empty-${controller.statusFilter}-${controller.providerFilter}',
                              ),
                            )
                          : ListView.builder(
                              key: ValueKey<String>(
                                'list-${controller.statusFilter}-${controller.providerFilter}',
                              ),
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                HudSpacing.xl,
                                HudSpacing.sm,
                                HudSpacing.xl,
                                HudSpacing.lg,
                              ),
                              itemCount: sessions.length,
                              findChildIndexCallback: (Key key) {
                                if (key is! ValueKey<String>) return null;
                                final int index = sessions.indexWhere(
                                    (session) => session.id == key.value);
                                return index == -1 ? null : index;
                              },
                              itemBuilder: (context, index) {
                                final AgentSession session = sessions[index];
                                return _AnimatedSessionCard(
                                  key: ValueKey<String>(session.id),
                                  session: session,
                                  index: index,
                                  entrance: _entrance,
                                  pulse: _pulse,
                                  reduced: _reduceMotion,
                                );
                              },
                            ),
                ),
              ),
            ),
            _Footer(
              lastUpdated: controller.lastUpdated,
              isRefreshing: controller.isRefreshing,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterOption {
  const _FilterOption(this.value, this.label, this.color, {this.icon});

  final String value;
  final String label;
  final Color color;
  final IconData? icon;
}

const List<_FilterOption> _statusOptions = [
  _FilterOption('All', '全部', HudColors.textPrimary,
      icon: Icons.grid_view_rounded),
  _FilterOption('Working', '工作', HudColors.working,
      icon: Icons.graphic_eq_rounded),
  _FilterOption('Waiting', '等待', HudColors.waiting, icon: Icons.help_rounded),
  _FilterOption('Completed', '完成', HudColors.completed,
      icon: Icons.check_rounded),
  _FilterOption('Failed', '错误', HudColors.failed,
      icon: Icons.priority_high_rounded),
];

const List<_FilterOption> _providerOptions = [
  _FilterOption('All', '全部', HudColors.textPrimary, icon: Icons.apps_rounded),
  _FilterOption('Codex', 'Codex', HudColors.codex,
      icon: Icons.terminal_rounded),
  _FilterOption('Claude', 'Claude', HudColors.claude,
      icon: Icons.auto_awesome_rounded),
  _FilterOption('Pi', 'Pi', HudColors.pi, icon: Icons.hexagon_outlined),
];

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: HudColors.window,
        border: Border(bottom: BorderSide(color: HudColors.divider)),
      ),
      padding: const EdgeInsets.only(top: HudSpacing.xs, bottom: HudSpacing.md),
      child: Column(
        children: [
          _FilterRow(
            options: _statusOptions,
            selected: controller.statusFilter,
            count: controller.countForStatus,
            onSelected: controller.setStatusFilter,
          ),
          _FilterRow(
            options: _providerOptions,
            selected: controller.providerFilter,
            count: controller.countForProvider,
            onSelected: controller.setProviderFilter,
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.options,
    required this.selected,
    required this.count,
    required this.onSelected,
  });

  final List<_FilterOption> options;
  final String selected;
  final int Function(String) count;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: HudSpacing.lg,
        vertical: HudSpacing.xxs,
      ),
      child: Row(
        children: [
          for (final _FilterOption option in options)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _FilterPill(
                option: option,
                selected: option.value == selected,
                count: count(option.value),
                onTap: () => onSelected(option.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.option,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final _FilterOption option;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected ? option.color : HudColors.textSecondary;
    final TextStyle baseStyle = DefaultTextStyle.of(context).style;
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label}，$count 个会话',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(HudRadii.panel),
          onTap: onTap,
          child: AnimatedContainer(
            duration: HudMotion.fast,
            curve: HudMotion.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? option.color.withValues(alpha: 0.16)
                  : HudColors.controlFill,
              borderRadius: BorderRadius.circular(HudRadii.panel),
              border: Border.all(
                color: selected
                    ? option.color.withValues(alpha: 0.52)
                    : HudColors.border,
                width: 0.9,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  option.icon ?? Icons.circle,
                  size: 12,
                  color: selected
                      ? option.color
                      : option.color.withValues(alpha: 0.62),
                ),
                const SizedBox(width: 5),
                AnimatedDefaultTextStyle(
                  duration: HudMotion.fast,
                  curve: HudMotion.easeOut,
                  style: baseStyle.copyWith(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: foreground,
                  ),
                  child: Text(option.label),
                ),
                const SizedBox(width: 5),
                AnimatedDefaultTextStyle(
                  duration: HudMotion.fast,
                  curve: HudMotion.easeOut,
                  style: baseStyle.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? option.color.withValues(alpha: 0.9)
                        : HudColors.textTertiary,
                  ),
                  child: Text('$count'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: HudMotion.base,
      curve: HudMotion.easeOut,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity, height: 0)
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                HudSpacing.xl,
                HudSpacing.sm,
                HudSpacing.xl,
                0,
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
                      message!,
                      style: HudText.caption.copyWith(color: HudColors.failed),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _AnimatedSessionCard extends StatelessWidget {
  const _AnimatedSessionCard({
    super.key,
    required this.session,
    required this.index,
    required this.entrance,
    required this.pulse,
    required this.reduced,
  });

  final AgentSession session;
  final int index;
  final Animation<double> entrance;
  final Animation<double> pulse;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final Widget card = Padding(
      padding: const EdgeInsets.only(bottom: HudSpacing.lg),
      child: _SessionCard(session: session, pulse: pulse, reduced: reduced),
    );

    if (reduced) return card;

    final double start = math.min(index * 0.045, 0.35);
    final double end = math.min(start + 0.55, 1);
    final Animation<double> animation = CurvedAnimation(
      parent: entrance,
      curve: Interval(start, end, curve: HudMotion.easeOut),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(animation),
        child: card,
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.pulse,
    required this.reduced,
  });

  final AgentSession session;
  final Animation<double> pulse;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final Color statusColor = HudColors.status(session.status);
    final bool outlined =
        HudColors.isActive(session.status) || session.status == 'Failed';

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              HudColors.surfaceRaised,
              outlined
                  ? statusColor.withValues(alpha: 0.06)
                  : HudColors.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(HudRadii.panel),
          border: Border.all(
            color: outlined
                ? statusColor.withValues(alpha: 0.38)
                : HudColors.border,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(HudRadii.panel),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SessionDetailPage(session: session),
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 3,
                      margin: const EdgeInsets.symmetric(
                        vertical: HudSpacing.lg,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HudSpacing.xl,
                  HudSpacing.lg,
                  HudSpacing.md,
                  HudSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HudText.title.copyWith(fontSize: 15.5),
                          ),
                        ),
                        const SizedBox(width: HudSpacing.md),
                        AnimatedSwitcher(
                          duration: HudMotion.fast,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: animation,
                              child: child,
                            ),
                          ),
                          child: HudStatusPill(
                            key: ValueKey<String>(session.status),
                            status: session.status,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: HudSpacing.sm),
                    Row(
                      children: [
                        HudProviderGlyph(provider: session.provider),
                        const SizedBox(width: HudSpacing.sm),
                        Expanded(
                          child: Text(
                            _metadata(session),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HudText.caption,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: HudSpacing.md),
                    Row(
                      children: [
                        _StatusDot(
                          color: statusColor,
                          pulsing:
                              HudColors.isActive(session.status) && !reduced,
                          pulse: pulse,
                        ),
                        const SizedBox(width: HudSpacing.sm),
                        Expanded(
                          child: Text(
                            session.currentAction,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                HudText.bodySecondary.copyWith(fontSize: 12.5),
                          ),
                        ),
                        const SizedBox(width: HudSpacing.md),
                        Text(
                          relativeTime(session.lastActivityAt),
                          style: HudText.caption.copyWith(
                            fontSize: 11,
                            color: HudColors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: HudSpacing.xxs),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: HudColors.textTertiary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _metadata(AgentSession session) {
    final StringBuffer buffer = StringBuffer()
      ..write(session.provider)
      ..write(' · ')
      ..write(session.projectName);
    final int changes = session.gitChangedFiles ?? 0;
    if (changes > 0) {
      buffer
        ..write(' · ')
        ..write(changes)
        ..write(' 个改动');
    }
    return buffer.toString();
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.color,
    required this.pulsing,
    required this.pulse,
  });

  final Color color;
  final bool pulsing;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    const double box = 14;
    if (!pulsing) {
      return SizedBox(
        width: box,
        height: box,
        child: Center(
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      );
    }
    return SizedBox(
      width: box,
      height: box,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, child) {
          final double value = pulse.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + value * 0.9,
                child: Opacity(
                  opacity: (1 - value) * 0.32,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: color,
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
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList({super.key, required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        return Opacity(opacity: 0.42 + pulse.value * 0.4, child: child);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          HudSpacing.xl,
          HudSpacing.sm,
          HudSpacing.xl,
          HudSpacing.lg,
        ),
        children: const [
          _SkeletonCard(),
          _SkeletonCard(),
          _SkeletonCard(),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: HudSpacing.lg),
      padding: const EdgeInsets.all(HudSpacing.xl),
      decoration: BoxDecoration(
        color: HudColors.surface,
        borderRadius: BorderRadius.circular(HudRadii.panel),
        border: Border.all(color: HudColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bar(widthFactor: 0.62, height: 12),
          const SizedBox(height: HudSpacing.md),
          _bar(widthFactor: 0.4, height: 8),
          const SizedBox(height: HudSpacing.lg),
          _bar(widthFactor: 0.78, height: 8),
        ],
      ),
    );
  }

  Widget _bar({required double widthFactor, required double height}) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: HudColors.controlFill,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        HudEntrance(
          child: Column(
            children: [
              Icon(
                Icons.radar_rounded,
                size: 34,
                color: HudColors.textTertiary,
              ),
              SizedBox(height: HudSpacing.lg),
              Text('当前筛选没有会话', style: HudText.title),
              SizedBox(height: HudSpacing.sm),
              Text(
                '下拉可刷新，或切换上方筛选条件。',
                style: HudText.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.lastUpdated, required this.isRefreshing});

  final DateTime? lastUpdated;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final String timeText = lastUpdated == null
        ? (isRefreshing ? '正在连接…' : '尚未连接')
        : '更新于 ${_time(lastUpdated!)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(
        HudSpacing.xl,
        HudSpacing.sm,
        HudSpacing.xl,
        HudSpacing.lg,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: HudColors.divider)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 13,
            color: HudColors.textTertiary,
          ),
          const SizedBox(width: HudSpacing.sm),
          const Text('只读监控', style: HudText.caption),
          const Spacer(),
          AnimatedSwitcher(
            duration: HudMotion.fast,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.centerRight,
              children: [
                ...previous,
                if (current != null) current,
              ],
            ),
            child: Text(
              timeText,
              key: ValueKey<String>(timeText),
              style: HudText.caption,
            ),
          ),
        ],
      ),
    );
  }

  static String _time(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }
}
