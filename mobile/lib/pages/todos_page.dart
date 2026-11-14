import 'dart:math' show Random;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../todo_store.dart';

class TodosPage extends StatefulWidget {
  const TodosPage({super.key});

  @override
  State<TodosPage> createState() => _TodosPageState();
}

class _TodosPageState extends State<TodosPage> {
  List<TodoItem> _todos = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await TodoStore.load();
    if (mounted) {
      setState(() {
        _todos = items;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    await TodoStore.save(_todos);
  }

  Future<void> _add() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _TodoEditorDialog(),
    );
    if (result == null || result.trim().isEmpty) return;
    final id = '${DateTime.now().millisecondsSinceEpoch}_${_randomId()}';
    final todo = TodoItem(
      id: id,
      title: result.trim(),
      createdAt: DateTime.now(),
    );
    setState(() => _todos = [todo, ..._todos]);
    await _save();
  }

  Future<void> _edit(TodoItem todo) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _TodoEditorDialog(initial: todo.title),
    );
    if (result == null) return;
    final trimmed = result.trim();
    if (trimmed.isEmpty) {
      _delete(todo);
      return;
    }
    final index = _todos.indexWhere((t) => t.id == todo.id);
    if (index < 0) return;
    setState(() {
      _todos = List<TodoItem>.of(_todos)
        ..[index] = todo.copyWith(title: trimmed);
    });
    await _save();
  }

  Future<void> _toggle(TodoItem todo) async {
    final index = _todos.indexWhere((t) => t.id == todo.id);
    if (index < 0) return;
    setState(() {
      _todos = List<TodoItem>.of(_todos)
        ..[index] = todo.copyWith(completed: !todo.completed);
    });
    await _save();
  }

  Future<void> _delete(TodoItem todo) async {
    setState(() => _todos = _todos.where((t) => t.id != todo.id).toList());
    await _save();
  }

  String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(6, (_) => chars[Random().nextInt(chars.length)])
        .join();
  }

  @override
  Widget build(BuildContext context) {
    final int remaining = _todos.where((todo) => !todo.completed).length;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 74,
        titleSpacing: HudSpacing.xl,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '待办',
              style: HudText.title.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.35,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _loading
                  ? '正在读取…'
                  : remaining == 0
                      ? (_todos.isEmpty ? '还没有记录' : '全部完成 · 共 ${_todos.length} 条')
                      : '$remaining 条未完成 · 共 ${_todos.length} 条',
              style: HudText.caption.copyWith(fontSize: 11.5),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: HudColors.divider),
        ),
        actions: [
          _HeaderIcon(
            tooltip: '新增待办',
            icon: Icons.add_rounded,
            onPressed: _add,
          ),
          const SizedBox(width: HudSpacing.lg),
        ],
      ),
      body: HudScaffoldBackground(
        child: AnimatedSwitcher(
          duration: HudMotion.base,
          switchInCurve: HudMotion.easeOut,
          switchOutCurve: HudMotion.easeIn,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: _loading
              ? const Center(
                  key: ValueKey<String>('loading'),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _todos.isEmpty
                  ? _EmptyTodos(key: const ValueKey<String>('empty'), onAdd: _add)
                  : ListView.builder(
                      key: const ValueKey<String>('list'),
                      padding: const EdgeInsets.fromLTRB(
                        HudSpacing.xl,
                        HudSpacing.lg,
                        HudSpacing.xl,
                        HudSpacing.xxl,
                      ),
                      itemCount: _todos.length,
                      itemBuilder: (context, index) {
                        final todo = _todos[index];
                        return _TodoCard(
                          todo: todo,
                          onToggle: () => _toggle(todo),
                          onEdit: () => _edit(todo),
                          onDelete: () => _delete(todo),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

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
            child: Icon(icon, size: 21, color: HudColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _TodoCard extends StatelessWidget {
  const _TodoCard({
    required this.todo,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final TodoItem todo;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(todo.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: HudSpacing.md),
        padding: const EdgeInsets.only(right: HudSpacing.xl),
        decoration: BoxDecoration(
          color: HudColors.failed.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: HudColors.failed,
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: HudSpacing.md),
        child: HudSurfaceCard(
          padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
          radius: 16,
          color: HudColors.surface.withValues(
            alpha: todo.completed ? 0.4 : 0.86,
          ),
          onTap: onEdit,
          child: Row(
            children: [
              IconButton(
                onPressed: onToggle,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 40, height: 40),
                icon: Icon(
                  todo.completed
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 21,
                  color: todo.completed
                      ? HudColors.completed
                      : HudColors.textTertiary,
                ),
              ),
              const SizedBox(width: HudSpacing.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        todo.title,
                        style: HudText.body.copyWith(
                          fontSize: 14.5,
                          height: 1.35,
                          decoration: todo.completed
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: HudColors.textTertiary,
                          color: todo.completed
                              ? HudColors.textTertiary
                              : HudColors.textPrimary,
                        ),
                      ),
                      if (todo.description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          todo.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: HudText.caption,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: HudSpacing.sm),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: HudColors.textTertiary.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTodos extends StatelessWidget {
  const _EmptyTodos({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        HudSpacing.xl,
        HudSpacing.xxl,
        HudSpacing.xl,
        HudSpacing.xxl,
      ),
      children: [
        HudEntrance(
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: HudColors.controlFill,
                  shape: BoxShape.circle,
                  border: Border.all(color: HudColors.border),
                ),
                child: Icon(
                  Icons.checklist_rounded,
                  size: 28,
                  color: HudColors.textTertiary.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: HudSpacing.xxl),
              Text(
                '还没有待办',
                style: HudText.title.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: HudSpacing.sm),
              Text(
                '把接下来要做的事记在这里，\n左滑可以删除。',
                textAlign: TextAlign.center,
                style: HudText.caption.copyWith(height: 1.6),
              ),
              const SizedBox(height: HudSpacing.xxl),
              SizedBox(
                width: 168,
                child: FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新增待办'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TodoEditorDialog extends StatefulWidget {
  const _TodoEditorDialog({this.initial});

  final String? initial;

  @override
  State<_TodoEditorDialog> createState() => _TodoEditorDialogState();
}

class _TodoEditorDialogState extends State<_TodoEditorDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '新增待办' : '编辑待办'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          hintText: '输入待办内容…',
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
