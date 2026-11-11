import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';

class SessionDetailPage extends StatelessWidget {
  const SessionDetailPage({super.key, required this.session});

  final AgentSession session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('会话详情')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(session.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('${session.provider} · ${session.projectName}', style: const TextStyle(color: Color(0xFF9AA8BA))),
          const SizedBox(height: 16),
          _Section(
            title: '当前进度',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusLabel(session.status), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(session.currentAction),
                if (session.currentFiles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final file in session.currentFiles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(file, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    ),
                ],
              ],
            ),
          ),
          if (session.summary != null && session.summary!.isNotEmpty)
            _Section(title: '最近总结', child: Text(session.summary!)),
          if (session.gitBranch != null)
            _Section(
              title: 'Git 上下文',
              child: Text(
                '${session.gitBranch} · ${session.gitChangedFiles ?? 0} 个文件 · +${session.gitInsertions ?? 0} / -${session.gitDeletions ?? 0}',
              ),
            ),
          _Section(
            title: '时间',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('开始：${_date(session.startedAt)}'),
                const SizedBox(height: 6),
                Text('最近活动：${_date(session.lastActivityAt)}'),
                if (session.completedAt != null) ...[
                  const SizedBox(height: 6),
                  Text('完成：${_date(session.completedAt!)}'),
                ],
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '此页面仅用于只读监控，不会向电脑发送控制命令。',
              style: TextStyle(fontSize: 12, color: Color(0xFF8B98AA)),
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime value) => DateFormat('yyyy-MM-dd HH:mm:ss').format(value.toLocal());
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
