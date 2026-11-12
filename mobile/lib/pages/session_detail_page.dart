import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/hud_chips.dart';

class SessionDetailPage extends StatelessWidget {
  const SessionDetailPage({super.key, required this.session});

  final AgentSession session;

  @override
  Widget build(BuildContext context) {
    final Color statusColor = HudColors.status(session.status);
    return Scaffold(
      appBar: AppBar(title: const Text('会话详情')),
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
                  _SectionCard(
                    title: '当前进度',
                    icon: Icons.bolt_rounded,
                    trailing: '置信度 ${_confidenceLabel(session.confidence)}',
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
                  if (session.summary != null && session.summary!.isNotEmpty)
                    _SectionCard(
                      title: '最近总结',
                      icon: Icons.checklist_rounded,
                      child: Text(session.summary!, style: HudText.body),
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
                  const SizedBox(height: HudSpacing.sm),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 13,
                        color: HudColors.textTertiary,
                      ),
                      SizedBox(width: HudSpacing.sm),
                      Flexible(
                        child: Text(
                          '此页面仅用于只读监控，不会向电脑发送控制命令。',
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
            statusColor.withValues(alpha: 0.07),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(HudRadii.hero),
        border: Border.all(color: statusColor.withValues(alpha: 0.34)),
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
              const Spacer(),
              HudStatusPill(status: session.status),
            ],
          ),
          const SizedBox(height: HudSpacing.lg),
          Text(session.title, style: HudText.display),
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
