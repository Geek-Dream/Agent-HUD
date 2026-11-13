import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../hidden_mode_store.dart';
import '../models.dart';
import '../session_controller.dart';
import '../theme.dart';
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
    _entrance = AnimationController(vsync: this, duration: HudMotion.entrance);
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.device.instanceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            Text(
              _subtitle(controller),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HudText.caption.copyWith(fontSize: 11),
            ),
          ],
        ),
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
              icon: const Icon(Icons.checklist_rounded, size: 21),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: () => controller.refresh(scan: true),
            icon: const Icon(Icons.refresh_rounded, size: 21),
          ),
          const SizedBox(width: HudSpacing.md),
        ],
      ),
      body: HudScaffoldBackground(
        child: Column(
          children: [
            _Filters(controller: controller),
            _ErrorBanner(message: controller.error),
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

  static String _subtitle(SessionController controller) {
    final int total = controller.totalCount;
    final int active = controller.sessions
        .where((session) => HudColors.isActive(session.status))
        .length;
    if (controller.lastUpdated == null) {
      return controller.isRefreshing ? '正在连接…' : '尚未连接';
    }
    if (active > 0) return '$active 个进行中 · 共 $total 个会话';
    return '$total 个会话 · 已同步';
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
  _FilterOption('All', '全部', HudColors.textPrimary),
  _FilterOption('Working', '进行中', HudColors.working),
  _FilterOption('Waiting', '等待', HudColors.waiting),
  _FilterOption('Completed', '已完成', HudColors.completed),
  _FilterOption('Failed', '出错', HudColors.failed),
  _FilterOption('Todo', '待办', HudColors.todo),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: HudSpacing.sm),
      child: Column(
        children: [
          _FilterRow(
            options: _statusOptions,
            selected: controller.statusFilter,
            count: controller.countForStatus,
            onSelected: controller.setStatusFilter,
          ),
          const SizedBox(height: HudSpacing.xs),
          _FilterRow(
            options: _providerOptions,
            selected: controller.providerFilter,
            count: controller.countForProvider,
            onSelected: controller.setProviderFilter,
            subtle: true,
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
    this.subtle = false,
  });

  final List<_FilterOption> options;
  final String selected;
  final int Function(String) count;
  final ValueChanged<String> onSelected;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: subtle ? 34 : 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: HudSpacing.xl),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: HudSpacing.sm),
        itemBuilder: (context, index) {
          final _FilterOption option = options[index];
          return _FilterChip(
            option: option,
            selected: option.value == selected,
            count: count(option.value),
            subtle: subtle,
            onTap: () => onSelected(option.value),
          );
        },
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
    this.subtle = false,
  });

  final _FilterOption option;
  final bool selected;
  final int count;
  final VoidCallback onTap;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final Color accent = option.color;
    final Color foreground = selected ? HudColors.textPrimary : HudColors.textTertiary;
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
            padding: EdgeInsets.symmetric(
              horizontal: subtle ? 11 : 12,
              vertical: subtle ? 6 : 7,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? HudColors.controlHover
                  : (subtle ? Colors.transparent : HudColors.controlFill),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? HudColors.borderStrong
                    : (subtle ? Colors.transparent : HudColors.border),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!subtle && option.value != 'All') ...[
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: selected ? accent : accent.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  option.label,
                  style: TextStyle(
                    fontSize: subtle ? 12 : 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: HudText.micro.copyWith(
                    fontSize: 10,
                    color: selected
                        ? HudColors.textTertiary
                        : HudColors.textTertiary.withValues(alpha: 0.7),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
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
    final Color statusColor = HudColors.status(session.status);
    final bool isActive = HudColors.isActive(session.status);
    final String? promptText = session.latestPrompt?.text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return HudSurfaceCard(
      onTap: onOpen,
      color: session.isImportant
          ? HudColors.important.withValues(alpha: 0.035)
          : HudColors.surface.withValues(alpha: 0.82),
      borderColor: session.isImportant
          ? HudColors.important.withValues(alpha: 0.22)
          : HudColors.border,
      padding: const EdgeInsets.fromLTRB(
        HudSpacing.xl,
        HudSpacing.lg,
        HudSpacing.lg,
        HudSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HudProviderGlyph(provider: session.provider, size: 24),
              const SizedBox(width: HudSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HudText.title,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _metadata(session),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HudText.caption.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HudSpacing.sm),
              HudStatusPill(
                status: session.status,
                pulsing: isActive && !reduced,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: HudSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  session.currentAction.isEmpty
                      ? '暂无进行中的动作'
                      : session.currentAction,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: HudText.bodySecondary.copyWith(fontSize: 13),
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
            ],
          ),
          if (promptText != null && promptText.isNotEmpty) ...[
            const SizedBox(height: HudSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: HudSpacing.md,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: HudColors.controlFill,
                borderRadius: BorderRadius.circular(HudRadii.micro),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      promptText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HudText.caption.copyWith(
                        color: HudColors.textSecondary,
                      ),
                    ),
                  ),
                  if (session.latestPrompt!.images.isNotEmpty) ...[
                    const SizedBox(width: HudSpacing.sm),
                    Icon(
                      Icons.image_outlined,
                      size: 12,
                      color: HudColors.textTertiary.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${session.latestPrompt!.images.length}',
                      style: HudText.caption.copyWith(fontSize: 10.5),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: HudSpacing.md),
          Row(
            children: [
              if (canStar)
                _StarButton(session: session, onStar: onStar)
              else
                const SizedBox(height: 28),
              const Spacer(),
              if (session.isImportant)
                Text(
                  '重要',
                  style: HudText.caption.copyWith(
                    fontSize: 10.5,
                    color: HudColors.important,
                  ),
                ),
              const SizedBox(width: HudSpacing.sm),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 15,
                color: HudColors.textTertiary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _metadata(AgentSession session) {
    final List<String> parts = <String>[
      session.provider,
      session.projectName,
    ];
    if (session.gitBranch != null && session.gitBranch!.isNotEmpty) {
      parts.add(session.gitBranch!);
    }
    final int changes = session.gitChangedFiles ?? 0;
    if (changes > 0) parts.add('$changes 个改动');
    if (session.hasCustomTitle) {
      parts.add(titleSourceLabel(session.titleSource));
    }
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
          padding: const EdgeInsets.all(4),
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
        HudSpacing.lg,
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
