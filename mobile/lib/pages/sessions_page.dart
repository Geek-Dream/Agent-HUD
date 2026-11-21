import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../device_store.dart';
import '../models.dart';
import '../session_controller.dart';
import '../session_preferences.dart';
import '../theme.dart';
import '../widgets/hud_chips.dart';
import 'session_detail_page.dart';
import 'session_settings_page.dart';
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
          displayPreferences: LocalSessionDisplayPreferences(),
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

  void _openSettings() {
    Navigator.of(context).push(
      HudSlidePageRoute<void>(
        builder: (_) => SessionSettingsPage(controller: _controller),
      ),
    );
  }

  void _openTodos() {
    Navigator.of(context).push(
      HudSlidePageRoute<void>(builder: (_) => const TodosPage()),
    );
  }

  Future<void> _openFilters() {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111823),
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SessionFilterSheet(
        controller: _controller,
        deviceName: widget.device.instanceName,
        onOpenSettings: _openSettings,
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
        toolbarHeight: 58,
        centerTitle: true,
        titleSpacing: 0,
        leadingWidth: 48,
        leading: _HeaderAction(
          tooltip: '返回',
          icon: Icons.arrow_back_ios_new_rounded,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          '项目任务',
          style: HudText.title.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        actions: [
          _HeaderAction(
            tooltip: '筛选与显示',
            icon: Icons.filter_list_rounded,
            onPressed: _openFilters,
          ),
          _HeaderAction(
            tooltip: '刷新',
            icon: Icons.refresh_rounded,
            busy: controller.isRefreshing,
            onPressed: () => controller.refresh(scan: true),
          ),
          const SizedBox(width: HudSpacing.md),
        ],
      ),
      body: HudScaffoldBackground(
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _TaskArcPainter()),
              ),
            ),
            Column(
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
                                        HudSpacing.xs,
                                        HudSpacing.xl,
                                        104,
                                      ),
                                      itemCount: sessions.length,
                                      findChildIndexCallback: (Key key) {
                                        if (key is! ValueKey<String>) {
                                          return null;
                                        }
                                        final int index = sessions.indexWhere(
                                          (session) => session.id == key.value,
                                        );
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
                                          onStar: () =>
                                              _toggleImportant(session),
                                          onOpen: () => _openSession(session),
                                        );
                                      },
                                    ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openTodos,
        backgroundColor: const Color(0xFFF2F5FA),
        foregroundColor: const Color(0xFF151B26),
        elevation: 5,
        highlightElevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        icon: const Icon(Icons.checklist_rounded, size: 18),
        label: const Text(
          '任务待办',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _SessionFilterSheet extends StatelessWidget {
  const _SessionFilterSheet({
    required this.controller,
    required this.deviceName,
    required this.onOpenSettings,
  });

  final SessionController controller;
  final String deviceName;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final bool filtered = controller.statusFilter != 'All' ||
            controller.providerFilter != 'All';
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '筛选与显示',
                            style: HudText.title.copyWith(
                              fontSize: 17,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            deviceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HudText.caption,
                          ),
                        ],
                      ),
                    ),
                    if (controller.status?.privacyMode == true)
                      const Tooltip(
                        message: '隐私模式已开启',
                        child: Icon(
                          Icons.visibility_off_outlined,
                          size: 19,
                          color: HudColors.waiting,
                        ),
                      ),
                    if (filtered)
                      TextButton(
                        onPressed: () {
                          controller.setStatusFilter('All');
                          controller.setProviderFilter('All');
                        },
                        child: const Text('重置'),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text('任务来源', style: HudText.label),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in _providerOptions)
                      _ProviderFilterChip(
                        option: option,
                        selected: controller.providerFilter == option.value,
                        count: controller.countForProvider(option.value),
                        onSelected: () =>
                            controller.setProviderFilter(option.value),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text('显示范围', style: HudText.label),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.035),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<SessionListLimit>(
                      value: controller.listLimit,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF182231),
                      borderRadius: BorderRadius.circular(10),
                      items: [
                        for (final limit in SessionListLimit.values)
                          DropdownMenuItem<SessionListLimit>(
                            value: limit,
                            child: Text(limit.label),
                          ),
                      ],
                      onChanged: (limit) {
                        if (limit != null) controller.setListLimit(limit);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '${controller.visibleSummary}，星标任务始终保留',
                  style: HudText.caption.copyWith(fontSize: 11),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onOpenSettings();
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 40),
                  ),
                  icon: const Icon(Icons.settings_outlined, size: 17),
                  label: const Text('更多显示设置'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProviderFilterChip extends StatelessWidget {
  const _ProviderFilterChip({
    required this.option,
    required this.selected,
    required this.count,
    required this.onSelected,
  });

  final _FilterOption option;
  final bool selected;
  final int count;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      avatar: option.value == 'All'
          ? const Icon(Icons.grid_view_rounded, size: 14)
          : Icon(hudProviderIcon(option.value), size: 14),
      label: Text('${option.label} $count'),
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return option.color.withValues(alpha: 0.18);
        }
        return Colors.white.withValues(alpha: 0.035);
      }),
      side: BorderSide(
        color: selected
            ? option.color.withValues(alpha: 0.42)
            : Colors.white.withValues(alpha: 0.07),
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        color: selected ? HudColors.textPrimary : HudColors.textSecondary,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    );
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
  _FilterOption('All', '全部', HudColors.textSecondary),
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
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 11),
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            for (final option in _statusOptions)
              Expanded(
                child: _FilterChip(
                  option: option,
                  selected: controller.statusFilter == option.value,
                  count: controller.countForStatus(option.value),
                  onTap: () => controller.setStatusFilter(option.value),
                ),
              ),
          ],
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
    final Color foreground =
        selected ? const Color(0xFF1B2230) : HudColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label}，$count 个会话',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: AnimatedContainer(
            duration: HudMotion.fast,
            curve: HudMotion.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFF0F3F8) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (option.value != 'All') ...[
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: option.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                  if (option.value == 'All') ...[
                    const SizedBox(width: 5),
                    Text(
                      '$count',
                      style: HudText.micro.copyWith(
                        fontSize: 10,
                        color: foreground,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
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
    final bool isWorking =
        session.status == 'Working' || session.status == 'Starting';
    final bool isActive = HudColors.isActive(session.status);
    final bool needsUser = session.status == 'WaitingUser';
    final Color statusColor = HudColors.status(session.status);
    final Color providerColor = HudColors.provider(session.provider);
    final Color baseColor =
        needsUser ? const Color(0xFF1B191B) : const Color(0xFF10161F);
    final String? meta = _metadata(session);

    return HudSurfaceCard(
      onTap: onOpen,
      color: baseColor,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(
            providerColor.withValues(alpha: isActive ? 0.065 : 0.045),
            baseColor,
          ),
          Color.alphaBlend(
            Colors.black.withValues(alpha: 0.12),
            baseColor,
          ),
        ],
      ),
      borderColor: needsUser
          ? HudColors.waiting.withValues(alpha: 0.22)
          : isWorking
              ? statusColor.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.075),
      radius: 14,
      shadows: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.22),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
        if (isWorking)
          BoxShadow(
            color: statusColor.withValues(alpha: 0.045),
            blurRadius: 16,
          ),
      ],
      padding: const EdgeInsets.fromLTRB(13, 13, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ProviderBadge(provider: session.provider),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HudText.title.copyWith(
                        fontSize: 14.5,
                        height: 1.25,
                        letterSpacing: 0,
                      ),
                    ),
                    if (meta != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HudText.caption.copyWith(
                          fontSize: 10.5,
                          height: 1.3,
                          color: HudColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: HudColors.textTertiary.withValues(alpha: 0.72),
              ),
            ],
          ),
          if (isActive && session.currentAction.isNotEmpty) ...[
            const SizedBox(height: 11),
            _ActiveSessionAction(
              action: session.currentAction,
              status: session.status,
              color: statusColor,
              pulse: pulse,
              animate: isWorking && !reduced,
            ),
          ],
          const SizedBox(height: 11),
          Row(
            children: [
              _TaskStatusPill(
                status: session.status,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  relativeTime(session.lastActivityAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HudText.caption.copyWith(
                    fontSize: 10.5,
                    color: HudColors.textTertiary,
                  ),
                ),
              ),
              if (canStar)
                _StarButton(session: session, onStar: onStar)
              else if (session.isImportant)
                const Icon(
                  Icons.star_rounded,
                  size: 18,
                  color: HudColors.important,
                ),
            ],
          ),
        ],
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
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }
}

class _ProviderBadge extends StatelessWidget {
  const _ProviderBadge({required this.provider});

  final String provider;

  @override
  Widget build(BuildContext context) {
    final Color color = HudColors.provider(provider);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.075),
          ],
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Icon(hudProviderIcon(provider), size: 20, color: color),
    );
  }
}

class _TaskStatusPill extends StatelessWidget {
  const _TaskStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color = HudColors.status(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(hudStatusIcon(status), size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            statusLabel(status),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveSessionAction extends StatelessWidget {
  const _ActiveSessionAction({
    required this.action,
    required this.status,
    required this.color,
    required this.pulse,
    required this.animate,
  });

  final String action;
  final String status;
  final Color color;
  final Animation<double> pulse;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        return Row(
          children: [
            Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.09),
                shape: BoxShape.circle,
              ),
              child: Icon(hudStatusIcon(status), size: 13, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                action,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HudText.bodySecondary.copyWith(
                  fontSize: 11.5,
                  height: 1.35,
                  color: HudColors.textSecondary.withValues(alpha: 0.86),
                ),
              ),
            ),
            if (animate) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 18,
                height: 15,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (var index = 0; index < 4; index++)
                      Container(
                        width: 2,
                        height: 4 +
                            8 *
                                (0.5 +
                                    0.5 *
                                        math.sin(
                                          (pulse.value + index * 0.17) *
                                              math.pi *
                                              2,
                                        )),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
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
        child: SizedBox(
          width: 30,
          height: 28,
          child: Center(
            child: Icon(
              widget.session.isImportant
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              size: 19,
              color: widget.session.isImportant
                  ? HudColors.important
                  : HudColors.textTertiary,
            ),
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

class _TaskArcPainter extends CustomPainter {
  const _TaskArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          HudColors.working.withValues(alpha: 0.12),
          HudColors.neon.withValues(alpha: 0.055),
          Colors.transparent,
        ],
        stops: const [0, 0.38, 0.72, 1],
      ).createShader(bounds);

    final Path lower = Path()
      ..moveTo(-size.width * 0.18, size.height * 0.79)
      ..cubicTo(
        size.width * 0.25,
        size.height * 0.96,
        size.width * 0.72,
        size.height * 0.67,
        size.width * 1.18,
        size.height * 0.84,
      );
    canvas.drawPath(lower, arc);

    final Path upper = Path()
      ..moveTo(-size.width * 0.25, size.height * 0.2)
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.06,
        size.width * 0.68,
        size.height * 0.27,
        size.width * 1.2,
        size.height * 0.12,
      );
    canvas.drawPath(upper, arc..strokeWidth = 0.7);
  }

  @override
  bool shouldRepaint(covariant _TaskArcPainter oldDelegate) => false;
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
