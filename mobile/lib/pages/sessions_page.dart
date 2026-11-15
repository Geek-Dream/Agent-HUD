import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../device_store.dart';
import '../models.dart';
import '../session_controller.dart';
import '../theme.dart';
import '../widgets/hud_chips.dart';
import 'session_detail_page.dart';
import 'todos_page.dart';

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key, required this.device, this.controller});

  final LinkedDevice device;

  /// Optional injected controller (used by previews and tests). When omitted the
  /// page owns and disposes its own controller.
  final SessionController? controller;

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final SessionController _controller;
  late final bool _ownsController;
  late final AnimationController _pulse;
  late final AnimationController _entrance;

  bool _reduceMotion = false;
  bool _entrancePlayed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(vsync: this, duration: HudMotion.pulse);
    _entrance = AnimationController(vsync: this, duration: HudMotion.entrance);
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        SessionController(
          widget.device,
          onDeviceUpdated: _persistDevice,
        );
    _controller.addListener(_changed);
    if (_ownsController) {
      _controller.start();
    } else if (_controller.sessions.isNotEmpty) {
      // Preview/test controllers may already hold data before the page mounts;
      // skip the staggered entrance so the first frame is not blank.
      _entrancePlayed = true;
      _entrance.value = 1;
    }
  }

  /// 电脑换网后服务端会回报新地址，写回本地，下次打开就不用再扫码。
  void _persistDevice(LinkedDevice device) {
    if (!mounted) return;
    unawaited(context.read<DeviceStore>().upsert(device));
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

  Future<void> _toggleImportant(AgentSession session) async {
    final bool applied =
        await _controller.setImportant(session, !session.isImportant);
    if (applied || !mounted) return;
    final String? message = _controller.actionError;
    if (message == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    _controller.clearActionError();
  }

  void _openSession(AgentSession session) {
    Navigator.of(context).push(
      HudSlidePageRoute<void>(
        builder: (_) => SessionDetailPage(
          controller: _controller,
          session: session,
        ),
      ),
    );
  }

  void _openTodos() {
    Navigator.of(context).push(
      HudSlidePageRoute<void>(builder: (_) => const TodosPage()),
    );
  }

  void _syncPulse() {
    if (!mounted) return;
    final bool active = _controller.sessions
        .any((session) => HudColors.isActive(session.status));
    final bool loading = _controller.isRefreshing &&
        _controller.lastUpdated == null &&
        _controller.sessions.isEmpty;
    if ((active || loading) && !_reduceMotion) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    if (_ownsController) _controller.dispose();
    _pulse.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.refresh(scan: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final SessionController controller = _controller;
    final List<AgentSession> sessions = controller.sessions;
    // 已经确定连不上时不能继续显示骨架屏，否则用户只会看到无限转圈。
    final bool disconnected = sessions.isEmpty &&
        controller.lastUpdated == null &&
        controller.error != null;
    final bool showSkeleton = sessions.isEmpty &&
        controller.lastUpdated == null &&
        controller.isRefreshing &&
        controller.error == null;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        titleSpacing: HudSpacing.xl,
        title: Row(
          children: [
            const _DeviceGlyph(),
            const SizedBox(width: HudSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.device.instanceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HudText.title.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.35,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(controller),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HudText.caption.copyWith(fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (controller.status?.privacyMode == true)
            const Tooltip(
              message: '隐私模式已开启',
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: HudSpacing.sm),
                child: Icon(
                  Icons.visibility_off_outlined,
                  size: 18,
                  color: HudColors.waiting,
                ),
              ),
            ),
          _ProviderFilterMenu(controller: controller, compact: true),
          _HeaderAction(
            tooltip: '待办',
            icon: Icons.checklist_rounded,
            onPressed: _openTodos,
          ),
          _HeaderAction(
            tooltip: '刷新',
            icon: Icons.refresh_rounded,
            busy: controller.isRefreshing,
            onPressed: () => controller.refresh(scan: true),
          ),
          const SizedBox(width: HudSpacing.xl),
        ],
      ),
      body: HudScaffoldBackground(
        child: Column(
          children: [
            _Filters(controller: controller),
            _ErrorBanner(message: disconnected ? null : controller.error),
            Expanded(
              child: RefreshIndicator(
                color: HudColors.textPrimary,
                backgroundColor: HudColors.surfaceRaised,
                onRefresh: () => controller.refresh(scan: true),
                child: AnimatedSwitcher(
                  duration: HudMotion.base,
                  switchInCurve: HudMotion.easeOut,
                  switchOutCurve: HudMotion.easeIn,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: showSkeleton
                      ? _SkeletonList(
                          key: const ValueKey<String>('skeleton'),
                          pulse: _pulse,
                        )
                      : disconnected
                          ? _DisconnectedList(
                              key: const ValueKey<String>('disconnected'),
                              message: controller.error!,
                              onRetry: () => controller.refresh(scan: true),
                              onRePair: () => Navigator.of(context).pop(),
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
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                    HudSpacing.xl,
                                    HudSpacing.md,
                                    HudSpacing.xl,
                                    HudSpacing.xl,
                                  ),
                                  itemCount: sessions.length,
                                  findChildIndexCallback: (Key key) {
                                    if (key is! ValueKey<String>) return null;
                                    final int index = sessions.indexWhere(
                                        (session) => session.id == key.value);
                                    return index == -1 ? null : index;
                                  },
                                  itemBuilder: (context, index) {
                                    final AgentSession session =
                                        sessions[index];
                                    return _AnimatedSessionCard(
                                      key: ValueKey<String>(session.id),
                                      session: session,
                                      index: index,
                                      entrance: _entrance,
                                      pulse: _pulse,
                                      reduced: _reduceMotion,
                                      canStar: controller.supportsActions,
                                      onStar: () => _toggleImportant(session),
                                      onOpen: () => _openSession(session),
                                    );
                                  },
                                ),
                ),
              ),
            ),
            _Footer(
              lastUpdated: controller.lastUpdated,
              isRefreshing: controller.isRefreshing,
              supportsActions: controller.supportsActions,
            ),
          ],
        ),
      ),
    );
  }

  static String _subtitle(SessionController controller) {
    final int total = controller.totalCount;
    final int active = controller.sessions
        .where((session) => HudColors.isActive(session.status))
        .length;
    if (controller.lastUpdated == null) {
      if (controller.error != null) return '连不上电脑';
      return controller.isRefreshing ? '正在连接…' : '尚未连接';
    }
    if (active > 0) return '$active 个进行中 · 共 $total 个会话';
    return '$total 个会话 · 已同步';
  }
}

class _FilterOption {
  const _FilterOption(this.value, this.label, this.color);

  final String value;
  final String label;
  final Color color;
}

const List<_FilterOption> _statusOptions = [
  _FilterOption('All', '全部', HudColors.textPrimary),
  _FilterOption('Working', '进行中', HudColors.working),
  _FilterOption('Waiting', '等待', HudColors.waiting),
  _FilterOption('Completed', '已完成', HudColors.completed),
  _FilterOption('Failed', '出错', HudColors.failed),
];

const List<_FilterOption> _providerOptions = [
  _FilterOption('All', '全部来源', HudColors.textSecondary),
  _FilterOption('Codex', 'Codex', HudColors.codex),
  _FilterOption('Claude', 'Claude', HudColors.claude),
  _FilterOption('Pi', 'Pi', HudColors.pi),
  _FilterOption('OpenCode', 'OpenCode', HudColors.opencode),
];

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: HudColors.divider)),
      ),
      padding: const EdgeInsets.only(bottom: HudSpacing.lg),
      child: _FilterRow(
        options: _statusOptions,
        selected: controller.statusFilter,
        count: controller.countForStatus,
        onSelected: controller.setStatusFilter,
      ),
    );
  }
}

/// Single compact control replacing the old second filter row: a quiet pill
/// that opens a small popup with the providers.
class _ProviderFilterMenu extends StatelessWidget {
  const _ProviderFilterMenu({required this.controller, this.compact = false});

  final SessionController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final String selected = controller.providerFilter;
    final bool active = selected != 'All';
    final Color accent =
        active ? HudColors.provider(selected) : HudColors.textTertiary;

    return PopupMenuButton<String>(
      tooltip: '按来源筛选',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      color: HudColors.surfaceRaised,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HudRadii.card),
        side: const BorderSide(color: HudColors.borderStrong),
      ),
      padding: EdgeInsets.zero,
      itemBuilder: (context) => [
        for (final _FilterOption option in _providerOptions)
          PopupMenuItem<String>(
            value: option.value,
            height: 40,
            child: Row(
              children: [
                if (option.value == 'All')
                  Icon(
                    Icons.apps_rounded,
                    size: 14,
                    color: HudColors.textTertiary,
                  )
                else
                  HudProviderGlyph(provider: option.value, size: 16),
                const SizedBox(width: HudSpacing.md),
                Text(
                  option.label,
                  style: HudText.bodySecondary.copyWith(
                    fontSize: 13,
                    fontWeight: option.value == selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: option.value == selected
                        ? HudColors.textPrimary
                        : HudColors.textSecondary,
                  ),
                ),
                const Spacer(),
                if (option.value == selected)
                  const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: HudColors.textSecondary,
                  ),
              ],
            ),
          ),
      ],
      onSelected: controller.setProviderFilter,
      child: compact
          ? SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.filter_alt_outlined,
                      size: 19,
                      color: active
                          ? HudColors.textPrimary
                          : HudColors.textSecondary,
                    ),
                    if (active)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: HudColors.provider(selected),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          : Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: active ? HudColors.controlHover : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active ? HudColors.borderStrong : HudColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_list_rounded, size: 13, color: accent),
                  const SizedBox(width: 5),
                  Text(
                    active ? selected : '来源',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active
                          ? HudColors.textPrimary
                          : HudColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 14,
                    color: HudColors.textTertiary,
                  ),
                ],
              ),
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
    return SizedBox(
      height: 30,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (Rect bounds) => const LinearGradient(
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.965, 1],
        ).createShader(bounds),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(
            left: HudSpacing.xl,
            right: HudSpacing.xxl,
          ),
          itemCount: options.length,
          separatorBuilder: (_, __) => const SizedBox(width: HudSpacing.sm),
          itemBuilder: (context, index) {
            final _FilterOption option = options[index];
            return _FilterChip(
              option: option,
              selected: option.value == selected,
              count: count(option.value),
              onTap: () => onSelected(option.value),
            );
          },
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
    final Color accent = option.color;
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label}，$count 个会话',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: AnimatedContainer(
            duration: HudMotion.fast,
            curve: HudMotion.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? HudColors.textPrimary : HudColors.controlFill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? Colors.transparent : HudColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (option.value != 'All') ...[
                  Container(
                    width: 4.5,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: selected ? 0.9 : 0.7),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected
                        ? HudColors.background
                        : HudColors.textSecondary,
                  ),
                ),
                if (selected || option.value == 'All') ...[
                  const SizedBox(width: 5),
                  Text(
                    '$count',
                    style: HudText.micro.copyWith(
                      fontSize: 10.5,
                      color: selected
                          ? HudColors.background.withValues(alpha: 0.5)
                          : HudColors.textTertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
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

class _AnimatedSessionCard extends StatefulWidget {
  const _AnimatedSessionCard({
    super.key,
    required this.session,
    required this.index,
    required this.entrance,
    required this.pulse,
    required this.reduced,
    required this.canStar,
    required this.onStar,
    required this.onOpen,
  });

  final AgentSession session;
  final int index;
  final Animation<double> entrance;
  final Animation<double> pulse;
  final bool reduced;
  final bool canStar;
  final VoidCallback onStar;
  final VoidCallback onOpen;

  @override
  State<_AnimatedSessionCard> createState() => _AnimatedSessionCardState();
}

class _AnimatedSessionCardState extends State<_AnimatedSessionCard>
    with TickerProviderStateMixin {
  late final AnimationController _appear;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(vsync: this, duration: HudMotion.entrance);
    if (!widget.reduced && widget.entrance.value >= 0.999) {
      _appear.forward(from: 0);
    } else {
      _appear.value = 1;
    }
  }

  @override
  void dispose() {
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget card = Padding(
      padding: const EdgeInsets.only(bottom: HudSpacing.lg),
      child: _SessionCard(
        session: widget.session,
        pulse: widget.pulse,
        reduced: widget.reduced,
        canStar: widget.canStar,
        onStar: widget.onStar,
        onOpen: widget.onOpen,
      ),
    );

    if (widget.reduced) return card;

    final Animation<double> appear = CurvedAnimation(
      parent: _appear,
      curve: HudMotion.easeOut,
    );
    final double start = math.min(widget.index * 0.045, 0.35);
    final double end = math.min(start + 0.55, 1);
    final Animation<double> entrance = CurvedAnimation(
      parent: widget.entrance,
      curve: Interval(start, end, curve: HudMotion.easeOut),
    );
    return FadeTransition(
      opacity: entrance,
      child: FadeTransition(
        opacity: appear,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(appear),
          child: card,
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.pulse,
    required this.reduced,
    required this.canStar,
    required this.onStar,
    required this.onOpen,
  });

  final AgentSession session;
  final Animation<double> pulse;
  final bool reduced;
  final bool canStar;
  final VoidCallback onStar;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final bool isActive = HudColors.isActive(session.status);
    final bool isWorking = session.status == 'Working' ||
        session.status == 'Starting';
    final bool needsUser = session.status == 'WaitingUser';
    final Color statusColor = HudColors.status(session.status);
    final String? meta = _metadata(session);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HudSurfaceCard(
        onTap: onOpen,
        color: needsUser ? HudColors.surfaceRaised : HudColors.surface,
        borderColor: needsUser
            ? HudColors.waiting.withValues(alpha: 0.28)
            : HudColors.border,
        radius: 18,
        accent: isActive ? statusColor : null,
        padding: const EdgeInsets.fromLTRB(15, 13, 10, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1, left: 2),
                  child: HudProviderGlyph(
                    provider: session.provider,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HudText.title.copyWith(
                          fontSize: 15.5,
                          height: 1.28,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (meta != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HudText.caption.copyWith(
                            fontSize: 11.5,
                            height: 1.3,
                            color: HudColors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 5, left: 8),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: HudColors.textTertiary.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
            if (session.currentAction.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2.5),
                      child: Icon(
                        hudStatusIcon(session.status),
                        size: 12.5,
                        color: statusColor.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        session.currentAction,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: HudText.bodySecondary.copyWith(
                          fontSize: 12.5,
                          height: 1.45,
                          color: HudColors.textSecondary.withValues(
                            alpha: 0.9,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              height: 1,
              margin: const EdgeInsets.only(left: 3, right: 6),
              color: HudColors.divider,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 3),
                HudStatusPill(
                  status: session.status,
                  dense: true,
                  pulsing: isWorking && !reduced,
                ),
                const SizedBox(width: 9),
                Text(
                  relativeTime(session.lastActivityAt),
                  style: HudText.caption.copyWith(
                    fontSize: 10.5,
                    color: HudColors.textTertiary.withValues(alpha: 0.8),
                  ),
                ),
                const Spacer(),
                if (canStar)
                  _StarButton(session: session, onStar: onStar)
                else if (session.isImportant)
                  Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: HudColors.important.withValues(alpha: 0.9),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Provider is implied by the glyph, so the meta line only carries context.
  static String? _metadata(AgentSession session) {
    final List<String> parts = <String>[];
    if (session.projectName.isNotEmpty) parts.add(session.projectName);
    if (session.gitBranch != null && session.gitBranch!.isNotEmpty) {
      parts.add(session.gitBranch!);
    }
    final int changes = session.gitChangedFiles ?? 0;
    if (changes > 0) parts.add('$changes 个改动');
    if (parts.isEmpty) return null;
    return parts.join('  ·  ');
  }
}

class _StarButton extends StatefulWidget {
  const _StarButton({required this.session, required this.onStar});

  final AgentSession session;
  final VoidCallback onStar;

  @override
  State<_StarButton> createState() => _StarButtonState();
}

class _StarButtonState extends State<_StarButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void didUpdateWidget(covariant _StarButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.isImportant != widget.session.isImportant) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 1.0, end: 1.2).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
      ),
      child: InkResponse(
        onTap: widget.onStar,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 0, 2),
          child: Icon(
            widget.session.isImportant
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            size: 18,
            color: widget.session.isImportant
                ? HudColors.important
                : HudColors.textTertiary,
          ),
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
        return Opacity(opacity: 0.35 + pulse.value * 0.3, child: child);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          HudSpacing.xl,
          HudSpacing.md,
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
      padding: const EdgeInsets.only(bottom: 32),
      children: const [
        SizedBox(height: 110),
        HudEntrance(
          child: Column(
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 30,
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

class _DisconnectedList extends StatelessWidget {
  const _DisconnectedList({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onRePair,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onRePair;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const SizedBox(height: 96),
        HudEntrance(
          child: Column(
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 30,
                color: HudColors.failed,
              ),
              const SizedBox(height: HudSpacing.lg),
              const Text('连不上电脑', style: HudText.title),
              const SizedBox(height: HudSpacing.sm),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: HudSpacing.xl),
                child: Text(
                  '电脑可能换了网络，或 AgentHUD 没有在运行。重新扫码关联会拿到最新地址。',
                  textAlign: TextAlign.center,
                  style: HudText.caption,
                ),
              ),
              const SizedBox(height: HudSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(onPressed: onRetry, child: const Text('重试')),
                  const SizedBox(width: HudSpacing.md),
                  TextButton(onPressed: onRePair, child: const Text('重新关联')),
                ],
              ),
              const SizedBox(height: HudSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: HudSpacing.xl),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: HudText.caption.copyWith(
                    fontSize: 11,
                    color: HudColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.lastUpdated,
    required this.isRefreshing,
    required this.supportsActions,
  });

  final DateTime? lastUpdated;
  final bool isRefreshing;
  final bool supportsActions;

  @override
  Widget build(BuildContext context) {
    final String timeText = lastUpdated == null
        ? (isRefreshing ? '正在连接…' : '尚未连接')
        : '更新于 ${_time(lastUpdated!)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(
        HudSpacing.xl,
        9,
        HudSpacing.xl,
        HudSpacing.lg,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: HudColors.divider)),
      ),
      child: Row(
        children: [
          Icon(
            supportsActions
                ? Icons.verified_user_outlined
                : Icons.visibility_outlined,
            size: 12,
            color: HudColors.textTertiary,
          ),
          const SizedBox(width: HudSpacing.sm),
          Text(
            supportsActions ? '局域网直连 · 可操作' : '只读监控',
            style: HudText.caption.copyWith(fontSize: 11),
          ),
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
              style: HudText.caption.copyWith(fontSize: 11),
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

/// Small square glyph shown in the header, matching the desktop HUD.
class _DeviceGlyph extends StatelessWidget {
  const _DeviceGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: HudColors.controlFill,
        borderRadius: BorderRadius.circular(HudRadii.control),
        border: Border.all(color: HudColors.border),
      ),
      child: const Icon(
        Icons.laptop_mac_rounded,
        size: 17,
        color: HudColors.textSecondary,
      ),
    );
  }
}

/// Quiet 36pt hit target for header actions with an inline busy state.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 20,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: HudColors.textSecondary,
                    ),
                  )
                : Icon(icon, size: 19, color: HudColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
