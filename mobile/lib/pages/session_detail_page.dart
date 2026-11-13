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
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocus = FocusNode();
  String? _lastClientMessageId;
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

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

  Future<void> _sendMessage(AgentSession session) async {
    final String text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    final String clientMessageId =
        _lastClientMessageId ?? DateTime.now().millisecondsSinceEpoch.toString();
    _lastClientMessageId = clientMessageId;
    setState(() => _sending = true);
    try {
      final MessageDelivery? delivery = await widget.controller.sendMessage(
        session,
        clientMessageId,
        text,
      );
      if (delivery == null && mounted) {
        _showActionError();
        return;
      }
      if (delivery != null && delivery.status != 'failed' && mounted) {
        _messageController.clear();
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Widget _buildMessageComposer(AgentSession session) {
    if (!widget.controller.supportsConversation) {
      return const SizedBox.shrink();
    }
    final ConversationState? conversation = session.conversation;
    final bool canSend = session.canSendMessage;
    final String? reason = conversation?.reason;
    final bool waitingUser = conversation?.state == 'waitingUser';

    return Container(
      padding: const EdgeInsets.fromLTRB(
        HudSpacing.xl,
        HudSpacing.md,
        HudSpacing.xl,
        HudSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: HudColors.window.withValues(alpha: 0.96),
        border: const Border(top: BorderSide(color: HudColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (waitingUser)
              Padding(
                padding: const EdgeInsets.only(bottom: HudSpacing.md),
                child: _ComposerNotice(
                  icon: Icons.pending_actions_rounded,
                  color: HudColors.waiting,
                  text: 'Agent 正在等待确认，你发送的内容将作为当前问题的回复。',
                ),
              ),
            if (!canSend && reason != null)
              Padding(
                padding: const EdgeInsets.only(bottom: HudSpacing.md),
                child: _ComposerNotice(
                  icon: Icons.block_outlined,
                  color: HudColors.failed,
                  text: reason,
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _messageFocus,
                    enabled: canSend && !_sending,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 4000,
                    textInputAction: TextInputAction.newline,
                    style: HudText.body,
                    decoration: InputDecoration(
                      hintText: canSend ? '输入任务或回复…' : '当前无法发送',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: HudSpacing.xl,
                        vertical: 13,
                      ),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _sendMessage(session),
                  ),
                ),
                const SizedBox(width: HudSpacing.md),
                _SendButton(
                  enabled: canSend && !_sending,
                  sending: _sending,
                  onTap: () => _sendMessage(session),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final AgentSession session =
            widget.controller.sessionById(widget.session.id) ?? widget.session;
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
              const SizedBox(width: HudSpacing.md),
            ],
          ),
          body: HudScaffoldBackground(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      HudSpacing.xl,
                      HudSpacing.sm,
                      HudSpacing.xl,
                      HudSpacing.xxl,
                    ),
                    children: [
                      HudEntrance(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _HeroCard(
                              session: session,
                              statusColor: statusColor,
                            ),
                            const SizedBox(height: HudSpacing.xl),
                            if (widget.controller.supportsPrompt)
                              _PromptCard(
                                controller: widget.controller,
                                session: session,
                                privacyMode: privacy,
                              ),
                            _SectionCard(
                              title: '当前进度',
                              trailing:
                                  '置信度 ${_confidenceLabel(session.confidence)}',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      HudStatusDot(
                                        color: statusColor,
                                        pulsing: false,
                                      ),
                                      const SizedBox(width: HudSpacing.md),
                                      Text(
                                        statusLabel(session.status),
                                        style: HudText.label.copyWith(
                                          color: statusColor,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        relativeTime(session.lastActivityAt),
                                        style: HudText.caption.copyWith(
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: HudSpacing.md),
                                  Text(
                                    session.currentAction.isEmpty
                                        ? '暂无进行中的动作'
                                        : session.currentAction,
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
                                              Icons.insert_drive_file_outlined,
                                              size: 13,
                                              color: HudColors.textTertiary,
                                            ),
                                            const SizedBox(width: HudSpacing.md),
                                            Expanded(
                                              child: Text(
                                                file,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: HudText.mono.copyWith(
                                                  fontSize: 11.5,
                                                ),
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
                                child: Text(
                                  session.summary!,
                                  style: HudText.body,
                                ),
                              ),
                            if (session.runs.isNotEmpty)
                              _SectionCard(
                                title: '完成记录',
                                child: _RunsList(runs: session.runs),
                              ),
                            if (session.gitBranch != null)
                              _SectionCard(
                                title: 'Git 上下文',
                                child: Column(
                                  children: [
                                    HudFactRow(
                                      label: '分支',
                                      value: session.gitBranch!,
                                      mono: true,
                                    ),
                                    HudFactRow(
                                      label: '改动文件',
                                      value:
                                          '${session.gitChangedFiles ?? 0} 个',
                                    ),
                                    if ((session.gitInsertions ?? 0) > 0 ||
                                        (session.gitDeletions ?? 0) > 0)
                                      HudFactRow(
                                        label: '增删行数',
                                        value:
                                            '+${session.gitInsertions ?? 0}  /  -${session.gitDeletions ?? 0}',
                                        valueColor: HudColors.completed,
                                        mono: true,
                                      ),
                                  ],
                                ),
                              ),
                            _SectionCard(
                              title: '时间',
                              child: Column(
                                children: [
                                  HudFactRow(
                                    label: '开始',
                                    value: _date(session.startedAt),
                                  ),
                                  HudFactRow(
                                    label: '最近活动',
                                    value: _date(session.lastActivityAt),
                                  ),
                                  if (session.completedAt != null)
                                    HudFactRow(
                                      label: '完成',
                                      value: _date(session.completedAt!),
                                      valueColor: HudColors.completed,
                                    ),
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
                                Icon(
                                  canEdit
                                      ? Icons.verified_user_outlined
                                      : Icons.visibility_outlined,
                                  size: 12,
                                  color: HudColors.textTertiary,
                                ),
                                const SizedBox(width: HudSpacing.sm),
                                Flexible(
                                  child: Text(
                                    canEdit
                                        ? '局域网直连 · 可重命名、星标与下发已授权的文本任务'
                                        : '此页面仅用于只读监控，不会向电脑发送控制命令',
                                    textAlign: TextAlign.center,
                                    style: HudText.caption.copyWith(
                                      fontSize: 11,
                                    ),
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
                _buildMessageComposer(session),
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

class _ComposerNotice extends StatelessWidget {
  const _ComposerNotice({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: HudSpacing.md),
        Expanded(
          child: Text(
            text,
            style: HudText.caption.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.sending,
    required this.onTap,
  });

  final bool enabled;
  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: HudMotion.fast,
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: HudColors.textPrimary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Center(
              child: sending
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: HudColors.background,
                      ),
                    )
                  : const Icon(
                      Icons.arrow_upward_rounded,
                      size: 20,
                      color: HudColors.background,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.session, required this.statusColor});

  final AgentSession session;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return HudSurfaceCard(
      padding: const EdgeInsets.all(HudSpacing.xl),
      color: HudColors.surface.withValues(alpha: 0.86),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HudProviderTag(provider: session.provider, size: 20),
              const Spacer(),
              HudStatusPill(status: session.status),
            ],
          ),
          const SizedBox(height: HudSpacing.xl),
          Text(
            session.title,
            style: HudText.display,
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
                  style: HudText.bodySecondary.copyWith(fontSize: 12.5),
                ),
              ),
              if (session.isImportant) ...[
                const Icon(
                  Icons.star_rounded,
                  size: 13,
                  color: HudColors.important,
                ),
                const SizedBox(width: 3),
              ],
              Text(
                session.hasCustomTitle
                    ? titleSourceLabel(session.titleSource)
                    : '自动标题',
                style: HudText.caption.copyWith(fontSize: 11),
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

    return HudSurfaceCard(
      margin: const EdgeInsets.only(bottom: HudSpacing.xl),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                HudSpacing.xl,
                HudSpacing.lg,
                HudSpacing.lg,
                HudSpacing.lg,
              ),
              child: Row(
                children: [
                  const Text('用户原始输入', style: HudText.label),
                  if (imageCount > 0) ...[
                    const SizedBox(width: HudSpacing.sm),
                    HudCountBadge(value: '图 $imageCount'),
                  ],
                  const Spacer(),
                  if (prompt?.sentAt != null)
                    Text(
                      DateFormat('MM-dd HH:mm')
                          .format(prompt!.sentAt!.toLocal()),
                      style: HudText.caption.copyWith(fontSize: 11),
                    ),
                  const SizedBox(width: HudSpacing.xs),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 19,
                    color: HudColors.textTertiary,
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
            ),
            child: SelectableText(
              prompt.text,
              style: HudText.body.copyWith(fontSize: 13.5),
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
        color: HudColors.waiting.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(HudRadii.control),
        border: Border.all(
          color: HudColors.waiting.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.visibility_off_outlined,
            size: 14,
            color: HudColors.waiting,
          ),
          const SizedBox(width: HudSpacing.md),
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
        for (int index = 0; index < runs.length; index++) ...[
          if (index > 0) const SizedBox(height: HudSpacing.md),
          Container(
            padding: const EdgeInsets.all(HudSpacing.lg),
            decoration: BoxDecoration(
              color: HudColors.controlFill,
              borderRadius: BorderRadius.circular(HudRadii.control),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        runs[index].objective,
                        style: HudText.body.copyWith(fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(width: HudSpacing.sm),
                    Text(
                      DateFormat('MM-dd HH:mm')
                          .format(runs[index].completedAt.toLocal()),
                      style: HudText.caption.copyWith(fontSize: 10.5),
                    ),
                  ],
                ),
                if (runs[index].summary.isNotEmpty) ...[
                  const SizedBox(height: HudSpacing.sm),
                  Text(
                    runs[index].summary,
                    style: HudText.bodySecondary.copyWith(fontSize: 12.5),
                  ),
                ],
                if (runs[index].actions.isNotEmpty) ...[
                  const SizedBox(height: HudSpacing.md),
                  Wrap(
                    spacing: HudSpacing.sm,
                    runSpacing: HudSpacing.sm,
                    children: [
                      for (final action in runs[index].actions)
                        _FactChip(
                          icon: Icons.bolt_rounded,
                          text: action,
                        ),
                    ],
                  ),
                ],
                if (runs[index].filesChanged.isNotEmpty) ...[
                  const SizedBox(height: HudSpacing.md),
                  for (final file in runs[index].filesChanged)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.insert_drive_file_outlined,
                            size: 12,
                            color: HudColors.textTertiary,
                          ),
                          const SizedBox(width: HudSpacing.sm),
                          Expanded(
                            child: Text(
                              file,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: HudText.mono.copyWith(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
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
        color: HudColors.failed.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(HudRadii.control),
        border: Border.all(color: HudColors.failed.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 14,
            color: HudColors.failed,
          ),
          const SizedBox(width: HudSpacing.md),
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
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return HudSurfaceCard(
      margin: const EdgeInsets.only(bottom: HudSpacing.lg),
      padding: const EdgeInsets.fromLTRB(
        HudSpacing.xl,
        HudSpacing.lg,
        HudSpacing.xl,
        HudSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: HudText.caption.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: HudColors.textTertiary,
                ),
              ),
              const Spacer(),
              if (trailing != null)
                Text(
                  trailing!,
                  style: HudText.caption.copyWith(fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: HudSpacing.md),
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
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
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
