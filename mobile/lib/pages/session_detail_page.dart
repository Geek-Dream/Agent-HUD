import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../session_controller.dart';
import '../theme.dart';
import '../widgets/hud_chips.dart';

class SessionDetailPage extends StatefulWidget {
  const SessionDetailPage({
    super.key,
    required this.controller,
    required this.session,
  });

  final SessionController controller;
  final AgentSession session;

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  Future<void> _toggleImportant(AgentSession session) async {
    final bool applied = await widget.controller.setImportant(
      session,
      !session.isImportant,
    );
    if (!applied && mounted) _showActionError();
  }

  Future<void> _rename(AgentSession session) async {
    final TextEditingController text = TextEditingController(
      text: session.title,
    );
    String? result;
    try {
      result = await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            backgroundColor: HudColors.surfaceRaised,
            title: const Text('重命名会话'),
            content: TextField(
              controller: text,
              autofocus: true,
              maxLength: 72,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '标题',
                hintText: '留空可恢复自动标题',
              ),
              onSubmitted: (String value) =>
                  Navigator.of(dialogContext).pop(value),
            ),
            actions: [
              if (session.hasCustomTitle)
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(''),
                  child: const Text('恢复自动'),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(text.text),
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    } finally {
      text.dispose();
    }
    if (result == null) return;
    final bool applied = await widget.controller.renameSession(
      session,
      result,
    );
    if (!applied && mounted) _showActionError();
  }

  void _showActionError() {
    final String? message = widget.controller.actionError;
    if (message == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final AgentSession session =
            widget.controller.sessionById(widget.session.id) ??
                widget.session;
        final Color statusColor = HudColors.status(session.status);
        final bool canEdit = widget.controller.supportsActions;
        final bool privacy = widget.controller.status?.privacyMode ?? false;

        return Scaffold(
          appBar: AppBar(
            title: const Text('会话详情'),
            actions: [
              if (canEdit)
                IconButton(
                  tooltip: session.isImportant ? '取消重要' : '标记为重要',
                  onPressed: () => _toggleImportant(session),
                  icon: Icon(
                    session.isImportant
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: session.isImportant
                        ? HudColors.important
                        : HudColors.textSecondary,
                  ),
                ),
              if (canEdit)
                IconButton(
                  tooltip: '重命名',
                  onPressed: () => _rename(session),
                  icon: const Icon(Icons.edit_rounded, size: 20),
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
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                HudSpacing.xl,
                HudSpacing.md,
                HudSpacing.xl,
                HudSpacing.xxl,
              ),
              children: [
                HudEntrance(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeroCard(session: session, statusColor: statusColor),
                      const SizedBox(height: HudSpacing.lg),
                      if (widget.controller.supportsPrompt)
                        _PromptCard(
                          controller: widget.controller,
                          session: session,
                          privacyMode: privacy,
                        ),
                      _SectionCard(
                        title: '当前进度',
                        icon: Icons.bolt_rounded,
                        trailing:
                            '置信度 ${_confidenceLabel(session.confidence)}',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: HudSpacing.sm),
                                Text(
                                  statusLabel(session.status),
                                  style: HudText.label.copyWith(
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: HudSpacing.md),
                            Text(
                              session.currentAction,
                              style: HudText.body,
                            ),
                            if (session.currentFiles.isNotEmpty) ...[
                              const SizedBox(height: HudSpacing.lg),
                              for (final String file
                                  in session.currentFiles.take(6))
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: HudSpacing.sm,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.description_outlined,
                                        size: 13,
                                        color: HudColors.textTertiary,
                                      ),
                                      const SizedBox(width: HudSpacing.sm),
                                      Expanded(
                                        child: Text(
                                          file,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: HudText.mono,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      if (session.summary != null &&
                          session.summary!.isNotEmpty)
                        _SectionCard(
                          title: '最近总结',
                          icon: Icons.checklist_rounded,
                          child: Text(session.summary!, style: HudText.body),
                        ),
                      if (session.runs.isNotEmpty)
                        _SectionCard(
                          title: '完成记录',
                          icon: Icons.history_rounded,
                          child: _RunsList(runs: session.runs),
                        ),
                      if (session.gitBranch != null)
                        _SectionCard(
                          title: 'Git 上下文',
                          icon: Icons.account_tree_outlined,
                          child: Wrap(
                            spacing: HudSpacing.sm,
                            runSpacing: HudSpacing.sm,
                            children: [
                              _FactChip(
                                icon: Icons.call_split_rounded,
                                text: session.gitBranch!,
                              ),
                              _FactChip(
                                icon: Icons.description_outlined,
                                text: '${session.gitChangedFiles ?? 0} 个改动',
                              ),
                              if ((session.gitInsertions ?? 0) > 0 ||
                                  (session.gitDeletions ?? 0) > 0)
                                _FactChip(
                                  icon: Icons.difference_rounded,
                                  text:
                                      '+${session.gitInsertions ?? 0} / -${session.gitDeletions ?? 0}',
                                  color: HudColors.completed,
                                ),
                            ],
                          ),
                        ),
                      _SectionCard(
                        title: '时间',
                        icon: Icons.schedule_rounded,
                        child: Column(
                          children: [
                            _TimeRow(
                              icon: Icons.play_arrow_rounded,
                              label: '开始',
                              value: _date(session.startedAt),
                            ),
                            const SizedBox(height: HudSpacing.sm),
                            _TimeRow(
                              icon: Icons.bolt_rounded,
                              label: '最近活动',
                              value: _date(session.lastActivityAt),
                            ),
                            if (session.completedAt != null) ...[
                              const SizedBox(height: HudSpacing.sm),
                              _TimeRow(
                                icon: Icons.check_rounded,
                                label: '完成',
                                value: _date(session.completedAt!),
                                color: HudColors.completed,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.controller.actionError != null)
                        _ActionError(
                          message: widget.controller.actionError!,
                          onDismiss: widget.controller.clearActionError,
                        ),
                      const SizedBox(height: HudSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            size: 13,
                            color: HudColors.textTertiary,
                          ),
                          const SizedBox(width: HudSpacing.sm),
                          Flexible(
                            child: Text(
                              canEdit
                                  ? '局域网直连 · 仅用于重命名、星标与查看，不会执行任务或修改会话状态。'
                                  : '此页面仅用于只读监控，不会向电脑发送控制命令。',
                              textAlign: TextAlign.center,
                              style: HudText.caption,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _confidenceLabel(String value) {
    switch (value) {
      case 'High':
        return '高';
      case 'Medium':
        return '中';
      case 'Low':
        return '低';
      default:
        return '未知';
    }
  }

  static String _date(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(value.toLocal());
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.session, required this.statusColor});

  final AgentSession session;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HudSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            HudColors.surfaceRaised,
            session.isImportant
                ? HudColors.important.withValues(alpha: 0.1)
                : statusColor.withValues(alpha: 0.07),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(HudRadii.hero),
        border: Border.all(
          color: session.isImportant
              ? HudColors.important.withValues(alpha: 0.5)
              : statusColor.withValues(alpha: 0.34),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HudProviderGlyph(provider: session.provider, size: 24),
              const SizedBox(width: HudSpacing.md),
              Text(
                session.provider,
                style: HudText.label.copyWith(
                  color: HudColors.provider(session.provider),
                ),
              ),
              if (session.isImportant) ...[
                const SizedBox(width: HudSpacing.sm),
                const Icon(
                  Icons.star_rounded,
                  size: 14,
                  color: HudColors.important,
                ),
                const SizedBox(width: 2),
                const Text(
                  '重要',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: HudColors.important,
                  ),
                ),
              ],
              const Spacer(),
              HudStatusPill(status: session.status),
            ],
          ),
          const SizedBox(height: HudSpacing.lg),
          Text(session.title, style: HudText.display),
          const SizedBox(height: HudSpacing.sm),
          Row(
            children: [
              Icon(
                session.hasCustomTitle
                    ? Icons.edit_note_rounded
                    : Icons.auto_awesome_rounded,
                size: 13,
                color: session.hasCustomTitle
                    ? HudColors.important
                    : HudColors.textTertiary,
              ),
              const SizedBox(width: HudSpacing.xs),
              Text(
                titleSourceLabel(session.titleSource),
                style: HudText.caption.copyWith(
                  color: session.hasCustomTitle
                      ? HudColors.important
                      : HudColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: HudSpacing.md),
          Row(
            children: [
              const Icon(
                Icons.folder_outlined,
                size: 14,
                color: HudColors.textTertiary,
              ),
              const SizedBox(width: HudSpacing.sm),
              Expanded(
                child: Text(
                  session.projectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HudText.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PromptCard extends StatefulWidget {
  const _PromptCard({
    required this.controller,
    required this.session,
    required this.privacyMode,
  });

  final SessionController controller;
  final AgentSession session;
  final bool privacyMode;

  @override
  State<_PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends State<_PromptCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final PromptSnapshot? prompt = widget.session.latestPrompt;
    final int imageCount = prompt?.images.length ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: HudSpacing.lg),
      decoration: BoxDecoration(
        color: HudColors.surface,
        borderRadius: BorderRadius.circular(HudRadii.panel),
        border: Border.all(
          color: prompt != null && !prompt.isEmpty
              ? HudColors.working.withValues(alpha: 0.24)
              : HudColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(HudRadii.panel),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                HudSpacing.xl,
                HudSpacing.lg,
                HudSpacing.xl,
                HudSpacing.lg,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.textsms_outlined,
                    size: 14,
                    color: HudColors.textSecondary,
                  ),
                  const SizedBox(width: HudSpacing.sm),
                  const Text('用户原始输入', style: HudText.label),
                  if (imageCount > 0) ...[
                    const SizedBox(width: HudSpacing.sm),
                    Icon(
                      Icons.photo_outlined,
                      size: 12,
                      color: HudColors.textTertiary,
                    ),
                    const SizedBox(width: 2),
                    Text('$imageCount', style: HudText.caption),
                  ],
                  const Spacer(),
                  if (prompt?.sentAt != null)
                    Text(
                      DateFormat('MM-dd HH:mm')
                          .format(prompt!.sentAt!.toLocal()),
                      style: HudText.caption.copyWith(fontSize: 10.5),
                    ),
                  const SizedBox(width: HudSpacing.sm),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: HudColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HudSpacing.xl,
                0,
                HudSpacing.xl,
                HudSpacing.xl,
              ),
              child: widget.privacyMode
                  ? const _PrivacyNotice()
                  : _promptBody(prompt, imageCount),
            ),
        ],
      ),
    );
  }

  Widget _promptBody(PromptSnapshot? prompt, int imageCount) {
    if (prompt == null) {
      return Text(
        '电脑尚未上报最近一次用户输入。',
        style: HudText.caption,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (prompt.text.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(HudSpacing.lg),
            decoration: BoxDecoration(
              color: HudColors.controlFill,
              borderRadius: BorderRadius.circular(HudRadii.control),
              border: Border.all(color: HudColors.divider),
            ),
            child: SelectableText(
              prompt.text,
              style: HudText.body.copyWith(fontSize: 13),
            ),
          ),
        if (imageCount > 0) ...[
          if (prompt.text.isNotEmpty) const SizedBox(height: HudSpacing.lg),
          Wrap(
            spacing: HudSpacing.md,
            runSpacing: HudSpacing.md,
            children: [
              for (final PromptImageRef image in prompt.images)
                _PromptImageTile(
                  key: ValueKey<String>('${widget.session.id}-${image.index}'),
                  controller: widget.controller,
                  sessionId: widget.session.id,
                  image: image,
                  allImages: prompt.images,
                ),
            ],
          ),
        ],
        if (prompt.text.isEmpty && imageCount == 0)
          Text('最近一次输入没有文本或图片。', style: HudText.caption),
      ],
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(HudSpacing.lg),
      decoration: BoxDecoration(
        color: HudColors.waiting.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(HudRadii.control),
        border: Border.all(
          color: HudColors.waiting.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.visibility_off_outlined,
            size: 14,
            color: HudColors.waiting,
          ),
          const SizedBox(width: HudSpacing.sm),
          Expanded(
            child: Text(
              '隐私模式已隐藏原始输入与图片',
              style: HudText.caption.copyWith(color: HudColors.waiting),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptImageTile extends StatefulWidget {
  const _PromptImageTile({
    super.key,
    required this.controller,
    required this.sessionId,
    required this.image,
    required this.allImages,
  });

  final SessionController controller;
  final String sessionId;
  final PromptImageRef image;
  final List<PromptImageRef> allImages;

  @override
  State<_PromptImageTile> createState() => _PromptImageTileState();
}

class _PromptImageTileState extends State<_PromptImageTile> {
  late Future<Uint8List?> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.controller.loadPromptImage(
      widget.sessionId,
      widget.image.index,
    );
  }

  @override
  void didUpdateWidget(covariant _PromptImageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.image.index != widget.image.index) {
      _bytes = widget.controller.loadPromptImage(
        widget.sessionId,
        widget.image.index,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(HudRadii.control),
        onTap: () => _showImageViewer(
          context,
          widget.controller,
          widget.sessionId,
          widget.allImages,
          widget.image.index,
        ),
        child: Container(
          width: 116,
          height: 96,
          decoration: BoxDecoration(
            color: HudColors.controlFill,
            borderRadius: BorderRadius.circular(HudRadii.control),
            border: Border.all(color: HudColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: FutureBuilder<Uint8List?>(
            future: _bytes,
            builder:
                (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final Uint8List? bytes = snapshot.data;
              if (bytes == null) {
                return _ImagePlaceholder(label: widget.image.label);
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: HudSpacing.sm,
                        vertical: HudSpacing.xs,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xCC000000)],
                        ),
                      ),
                      child: Text(
                        widget.image.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HudText.caption.copyWith(
                          fontSize: 9.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            size: 20,
            color: HudColors.textTertiary,
          ),
          const SizedBox(height: HudSpacing.xs),
          Text(label, style: HudText.caption.copyWith(fontSize: 9.5)),
          Text(
            '不可用',
            style: HudText.caption.copyWith(fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}

void _showImageViewer(
  BuildContext context,
  SessionController controller,
  String sessionId,
  List<PromptImageRef> images,
  int initialIndex,
) {
  final int start = images.indexWhere(
    (PromptImageRef item) => item.index == initialIndex,
  );
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (BuildContext dialogContext) {
      return _PromptImageViewer(
        controller: controller,
        sessionId: sessionId,
        images: images,
        initialPage: start < 0 ? 0 : start,
      );
    },
  );
}

class _PromptImageViewer extends StatefulWidget {
  const _PromptImageViewer({
    required this.controller,
    required this.sessionId,
    required this.images,
    required this.initialPage,
  });

  final SessionController controller;
  final String sessionId;
  final List<PromptImageRef> images;
  final int initialPage;

  @override
  State<_PromptImageViewer> createState() => _PromptImageViewerState();
}

class _PromptImageViewerState extends State<_PromptImageViewer> {
  late final PageController _pages;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialPage;
    _pages = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.images.length,
              onPageChanged: (int value) => setState(() => _index = value),
              itemBuilder: (BuildContext context, int index) {
                final PromptImageRef image = widget.images[index];
                return FutureBuilder<Uint8List?>(
                  future: widget.controller.loadPromptImage(
                    widget.sessionId,
                    image.index,
                  ),
                  builder: (BuildContext context,
                      AsyncSnapshot<Uint8List?> snapshot) {
                    final Uint8List? bytes = snapshot.data;
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (bytes == null) {
                      return const Center(
                        child: Text('图片已不可用', style: HudText.body),
                      );
                    }
                    return InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Center(
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HudSpacing.md,
                  vertical: HudSpacing.sm,
                ),
                child: Row(
                  children: [
                    Text(
                      '${widget.images[_index].label}  ${_index + 1}/${widget.images.length}',
                      style: HudText.label,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RunsList extends StatelessWidget {
  const _RunsList({required this.runs});

  final List<TaskRun> runs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final run in runs)
          Container(
            margin: const EdgeInsets.only(bottom: HudSpacing.md),
            padding: const EdgeInsets.all(HudSpacing.lg),
            decoration: BoxDecoration(
              color: HudColors.controlFill,
              borderRadius: BorderRadius.circular(HudRadii.control),
              border: Border.all(color: HudColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        run.objective,
                        style: HudText.label.copyWith(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: HudSpacing.sm),
                    Text(
                      DateFormat('MM-dd HH:mm').format(run.completedAt.toLocal()),
                      style: HudText.caption.copyWith(fontSize: 10.5),
                    ),
                  ],
                ),
                if (run.summary.isNotEmpty) ...[
                  const SizedBox(height: HudSpacing.sm),
                  Text(run.summary, style: HudText.bodySecondary),
                ],
                if (run.actions.isNotEmpty) ...[
                  const SizedBox(height: HudSpacing.sm),
                  Wrap(
                    spacing: HudSpacing.sm,
                    runSpacing: HudSpacing.sm,
                    children: [
                      for (final action in run.actions)
                        _FactChip(
                          icon: Icons.bolt_rounded,
                          text: action,
                        ),
                    ],
                  ),
                ],
                if (run.filesChanged.isNotEmpty) ...[
                  const SizedBox(height: HudSpacing.sm),
                  Wrap(
                    spacing: HudSpacing.sm,
                    runSpacing: HudSpacing.sm,
                    children: [
                      for (final file in run.filesChanged)
                        _FactChip(
                          icon: Icons.description_outlined,
                          text: file,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ActionError extends StatelessWidget {
  const _ActionError({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: HudSpacing.lg),
      padding: const EdgeInsets.fromLTRB(
        HudSpacing.lg,
        HudSpacing.sm,
        HudSpacing.sm,
        HudSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: HudColors.failed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(HudRadii.control),
        border: Border.all(color: HudColors.failed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 14,
            color: HudColors.failed,
          ),
          const SizedBox(width: HudSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: HudText.caption.copyWith(color: HudColors.failed),
            ),
          ),
          TextButton(onPressed: onDismiss, child: const Text('知道了')),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? trailing;

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
          Row(
            children: [
              Icon(icon, size: 14, color: HudColors.textSecondary),
              const SizedBox(width: HudSpacing.sm),
              Text(title, style: HudText.label),
              const Spacer(),
              if (trailing != null)
                Text(
                  trailing!,
                  style: HudText.caption.copyWith(fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: HudSpacing.lg),
          child,
        ],
      ),
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({
    required this.icon,
    required this.text,
    this.color = HudColors.textSecondary,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: HudColors.controlFill,
        borderRadius: BorderRadius.circular(HudRadii.micro),
        border: Border.all(color: HudColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.icon,
    required this.label,
    required this.value,
    this.color = HudColors.textTertiary,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: HudSpacing.sm),
        SizedBox(
          width: 72,
          child: Text(label, style: HudText.caption),
        ),
        Expanded(
          child: Text(
            value,
            style: HudText.bodySecondary.copyWith(
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
