import 'package:flutter/material.dart';

import '../models.dart';
import '../session_controller.dart';
import 'session_detail_page.dart';

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key, required this.device});

  final LinkedDevice device;

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> with WidgetsBindingObserver {
  late final SessionController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = SessionController(widget.device)
      ..addListener(_changed)
      ..start();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_changed)
      ..dispose();
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
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.instanceName),
        actions: [
          if (controller.status?.privacyMode == true)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.visibility_off, size: 20),
            ),
          IconButton(onPressed: controller.refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          _Filters(controller: controller),
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Text(controller.error!, style: const TextStyle(color: Color(0xFFFFB4BF))),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: controller.sessions.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 160),
                        Center(child: Text('当前筛选没有会话')),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                      itemCount: controller.sessions.length,
                      itemBuilder: (context, index) {
                        final session = controller.sessions[index];
                        return _SessionCard(session: session);
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 14, color: Color(0xFF8B98AA)),
                const SizedBox(width: 6),
                const Text('只读监控', style: TextStyle(fontSize: 12, color: Color(0xFF8B98AA))),
                const Spacer(),
                Text(
                  controller.lastUpdated == null ? '正在连接…' : '更新于 ${_time(controller.lastUpdated!)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8B98AA)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF101722),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          _chipRow(
            const [('All', '全部'), ('Working', '工作'), ('Waiting', '等待'), ('Completed', '完成'), ('Failed', '错误')],
            controller.statusFilter,
            controller.setStatusFilter,
          ),
          _chipRow(
            const [('All', '全部'), ('Codex', 'Codex'), ('Claude', 'Claude'), ('Pi', 'Pi')],
            controller.providerFilter,
            controller.setProviderFilter,
          ),
        ],
      ),
    );
  }

  Widget _chipRow(List<(String, String)> values, String selected, ValueChanged<String> onSelected) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        children: [
          for (final value in values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                label: Text(value.$2),
                selected: selected == value.$1,
                onSelected: (_) => onSelected(value.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final AgentSession session;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (session.status) {
      'Working' || 'Starting' => const Color(0xFF60A5FA),
      'WaitingUser' => const Color(0xFFFBBF24),
      'Completed' => const Color(0xFF34D399),
      'Failed' => const Color(0xFFFF7A8C),
      _ => const Color(0xFF9AA8BA),
    };
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => SessionDetailPage(session: session)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(15),
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
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(statusLabel(session.status), style: TextStyle(color: statusColor, fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${session.provider} · ${session.projectName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8BA)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.circle, size: 7, color: statusColor),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      session.currentAction,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(relativeTime(session.lastActivityAt), style: const TextStyle(fontSize: 11, color: Color(0xFF8B98AA))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
