import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../session_controller.dart';
import '../theme.dart';
import '../hidden_mode_store.dart';
import '../widgets/hud_chips.dart';
import 'session_detail_page.dart';
import 'todos_page.dart';

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
  bool _hiddenMode = false;

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
    _loadHiddenMode();
  }

  Future<void> _loadHiddenMode() async {
    final enabled = await HiddenModeStore.isEnabled();
    if (mounted) setState(() => _hiddenMode = enabled);
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
    if (_controller.statusFilter == 'Todo') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.setStatusFilter('All');
        _openTodos();
      });
      return;
    }
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
      HudSlidePageRoute<void>(
        builder: (_) => const TodosPage(),
      ),
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
      _controller.refresh(scan: true);
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
          if (_hiddenMode)
            IconButton(
              tooltip: '待办',
              onPressed: _openTodos,
              icon: const Icon(Icons.checklist_rounded, size: 21, color: HudColors.todo),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: () => controller.refresh(scan: true),
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
                onRefresh: () => controller.refresh(scan: true),
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
  _FilterOption('Todo', '待办', HudColors.todo,
      icon: Icons.checklist_rounded),
];

const List<_FilterOption> _providerOptions = [
  _FilterOption('All', '全部', HudColors.textPrimary, icon: Icons.apps_rounded),
  _FilterOption('Codex', 'Codex', HudColors.codex,
      icon: Icons.terminal_rounded),
  _FilterOption('Claude', 'Claude', HudColors.claude,
      icon: Icons.auto_awesome_rounded),
  _FilterOption('Pi', 'Pi', HudColors.pi, icon: Icons.hexagon_outlined),
  _FilterOption('OpenCode', 'OpenCode', HudColors.opencode,
      icon: Icons.code_rounded),
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
            tech: true,
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
    this.tech = false,
  });

  final List<_FilterOption> options;
  final String selected;
  final int Function(String) count;
  final ValueChanged<String> onSelected;
  final bool tech;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: HudSpacing.md,
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
                tech: tech,
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
    this.tech = false,
  });

  final _FilterOption option;
  final bool selected;
  final int count;
  final VoidCallback onTap;
  final bool tech;

  @override
  Widget build(BuildContext context) {
    final Color color = option.color;
    final Color foreground = selected ? color : HudColors.textSecondary;
    final TextStyle baseStyle = DefaultTextStyle.of(context).style;
    final ShapeBorder shape = tech
        ? HudChamferBorder(
            cut: 6,
            side: BorderSide(
              color: selected
                  ? color.withValues(alpha: 0.86)
                  : HudColors.border,
              width: selected ? 1.1 : 0.9,
            ),
          )
        : StadiumBorder(
            side: BorderSide(
              color: selected
                  ? color.withValues(alpha: 0.58)
                  : HudColors.border,
              width: selected ? 1.1 : 0.9,
            ),
          );

    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label}，$count 个会话',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: AnimatedContainer(
            duration: HudMotion.fast,
            curve: HudMotion.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: tech ? 11 : 12,
              vertical: 6.5,
            ),
            decoration: ShapeDecoration(
              color: selected
                  ? color.withValues(alpha: tech ? 0.22 : 0.18)
                  : HudColors.controlFill,
              shape: shape,
              shadows: selected
                  ? <BoxShadow>[
                      BoxShadow(
                        color: color.withValues(alpha: tech ? 0.45 : 0.28),
                        blurRadius: tech ? 20 : 14,
                        spreadRadius: tech ? 2 : 1,
                      ),
                      BoxShadow(
                        color: color.withValues(alpha: tech ? 0.18 : 0.12),
                        blurRadius: tech ? 8 : 6,
                        spreadRadius: 0,
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (selected && tech)
                  Positioned(
                    top: 0,
                    left: 9,
                    right: 9,
                    child: Container(
                      height: 1.2,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.9),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: color.withValues(alpha: 0.75),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      option.icon ?? Icons.circle,
                      size: 12,
                      color: selected
                          ? color
                          : color.withValues(alpha: 0.62),
                    ),
                    const SizedBox(width: 5),
                    AnimatedDefaultTextStyle(
                      duration: HudMotion.fast,
                      curve: HudMotion.easeOut,
                      style: baseStyle.copyWith(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
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
                            ? color.withValues(alpha: 0.9)
                            : HudColors.textTertiary,
                      ),
                      child: Text('$count'),
                    ),
                  ],
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
  late final AnimationController _transition;
  late final AnimationController _appear;
  AgentSession? _previous;

  @override
  void initState() {
    super.initState();
    _transition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    )..addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _previous = null);
        }
      });
    _appear = AnimationController(
      vsync: this,
      duration: HudMotion.entrance,
    );
    if (!widget.reduced && widget.entrance.value >= 0.999) {
      _appear.forward(from: 0);
    } else {
      _appear.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedSessionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.status == widget.session.status) return;
    if (widget.reduced) {
      _previous = null;
      _transition.value = 1;
      return;
    }
    _previous = oldWidget.session;
    _transition.forward(from: 0);
  }

  @override
  void dispose() {
    _transition.dispose();
    _appear.dispose();
    super.dispose();
  }

  Widget _buildCard(AgentSession session) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HudSpacing.lg),
      child: _SessionCard(
        session: session,
        pulse: widget.pulse,
        reduced: widget.reduced,
        canStar: widget.canStar,
        onStar: widget.onStar,
        onOpen: widget.onOpen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AgentSession? previous = _previous;
    Widget card;
    if (previous == null) {
      card = _buildCard(widget.session);
    } else {
      card = AnimatedBuilder(
        animation: _transition,
        builder: (BuildContext context, Widget? child) {
          final double value = _transition.value;
          final double outgoing = Curves.easeInCubic.transform(
            (value / 0.5).clamp(0.0, 1.0),
          );
          final double incoming = Curves.easeOutCubic.transform(
            ((value - 0.42) / 0.58).clamp(0.0, 1.0),
          );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Opacity(
                opacity: incoming,
                child: FractionalTranslation(
                  translation: Offset(0, (1 - incoming) * 0.42),
                  child: _buildCard(widget.session),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: (1 - outgoing) * 0.92,
                    child: FractionalTranslation(
                      translation: Offset(outgoing * 0.9, 0),
                      child: _buildCard(previous),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    if (widget.reduced) return card;

    final Animation<double> appear = CurvedAnimation(
      parent: _appear,
      curve: HudMotion.easeOut,
    );
    final Widget appeared = FadeTransition(
      opacity: appear,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.09),
          end: Offset.zero,
        ).animate(appear),
        child: card,
      ),
    );

    final double start = math.min(widget.index * 0.045, 0.35);
    final double end = math.min(start + 0.55, 1);
    final Animation<double> entrance = CurvedAnimation(
      parent: widget.entrance,
      curve: Interval(start, end, curve: HudMotion.easeOut),
    );
    return FadeTransition(
      opacity: entrance,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(entrance),
        child: appeared,
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
    final Color statusColor = HudColors.status(session.status);
    final bool outlined =
        HudColors.isActive(session.status) || session.status == 'Failed';
    final bool isActive = HudColors.isActive(session.status);
    final Color borderColor = session.isImportant
        ? HudColors.important.withValues(alpha: 0.55)
        : outlined
            ? statusColor.withValues(alpha: 0.38)
            : HudColors.border;

    return Container(
      margin: const EdgeInsets.only(bottom: HudSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HudRadii.panel),
        boxShadow: session.isImportant
            ? HudElevation.glow(HudColors.important)
            : outlined
                ? HudElevation.card(statusColor.withValues(alpha: 0.25))
                : HudElevation.card(HudColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(HudRadii.panel),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                HudColors.surfaceRaised,
                session.isImportant
                    ? HudColors.important.withValues(alpha: 0.09)
                    : outlined
                        ? statusColor.withValues(alpha: 0.07)
                        : HudColors.surface,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(HudRadii.panel),
            border: Border.all(
              color: borderColor,
              width: session.isImportant ? 1.2 : 1.0,
            ),
          ),
          child: InkWell(
            onTap: onOpen,
            highlightColor: HudColors.controlHover.withValues(alpha: 0.35),
            splashColor: HudColors.controlFill.withValues(alpha: 0.45),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: HudMotion.fast,
                        width: session.isImportant ? 4 : 3,
                        margin: EdgeInsets.symmetric(
                          vertical: session.isImportant
                              ? HudSpacing.md
                              : HudSpacing.lg,
                        ),
                        decoration: BoxDecoration(
                          color: (session.isImportant
                                  ? HudColors.important
                                  : statusColor)
                              .withValues(alpha: session.isImportant ? 0.9 : 0.72),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: session.isImportant
                              ? [
                                  BoxShadow(
                                    color: HudColors.important
                                        .withValues(alpha: 0.4),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
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
                          if (canStar) _StarButton(session: session, onStar: onStar),
                          const SizedBox(width: HudSpacing.xxs),
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
                              pulsing: isActive && !reduced,
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
                          HudStatusDot(
                            color: statusColor,
                            pulsing: isActive && !reduced,
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
                      if (session.latestPrompt != null &&
                          !session.latestPrompt!.isEmpty) ...[
                        const SizedBox(height: HudSpacing.md),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: HudSpacing.md,
                            vertical: HudSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: HudColors.controlFill,
                            borderRadius: BorderRadius.circular(HudRadii.micro),
                            border: Border.all(color: HudColors.divider),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.format_quote_rounded,
                                size: 12,
                                color: HudColors.textTertiary,
                              ),
                              const SizedBox(width: HudSpacing.sm),
                              Expanded(
                                child: Text(
                                  session.latestPrompt!.text
                                      .replaceAll(RegExp(r'\s+'), ' ')
                                      .trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: HudText.caption.copyWith(
                                    color: HudColors.textSecondary,
                                  ),
                                ),
                              ),
                              if (session.latestPrompt!.images.isNotEmpty) ...[
                                const SizedBox(width: HudSpacing.sm),
                                const Icon(
                                  Icons.photo_outlined,
                                  size: 12,
                                  color: HudColors.textTertiary,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${session.latestPrompt!.images.length}',
                                  style: HudText.caption.copyWith(fontSize: 10.5),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
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
    if (session.hasCustomTitle) {
      buffer
        ..write(' · ')
        ..write(titleSourceLabel(session.titleSource));
    }
    return buffer.toString();
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
      scale: Tween<double>(begin: 1.0, end: 1.25).animate(
        CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
      ),
      child: IconButton(
        onPressed: widget.onStar,
        tooltip:
            widget.session.isImportant ? '取消重要' : '标记为重要',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: 30,
          height: 30,
        ),
        iconSize: 17,
        icon: Icon(
          widget.session.isImportant
              ? Icons.star_rounded
              : Icons.star_outline_rounded,
          color: widget.session.isImportant
              ? HudColors.important
              : HudColors.textTertiary,
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
      padding: const EdgeInsets.only(bottom: 32),
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
        HudSpacing.sm,
        HudSpacing.xl,
        HudSpacing.xl,
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
          Text(
            supportsActions ? '证书固定 · 可改名/星标' : '只读监控',
            style: HudText.caption,
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
