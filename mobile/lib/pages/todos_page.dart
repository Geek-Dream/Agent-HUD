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
    return Scaffold(
      appBar: AppBar(
        title: const Text('待办'),
        actions: [
          IconButton(
            tooltip: '新增待办',
            onPressed: _add,
            icon: const Icon(Icons.add_rounded, size: 22),
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
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _todos.isEmpty
                ? _EmptyTodos(onAdd: _add)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      HudSpacing.xl,
                      HudSpacing.sm,
                      HudSpacing.xl,
                      HudSpacing.lg,
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
        padding: const EdgeInsets.only(right: HudSpacing.xl),
        decoration: BoxDecoration(
          color: HudColors.failed.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(HudRadii.panel),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: HudColors.failed),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: HudSpacing.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              HudColors.surfaceRaised,
              todo.completed
                  ? HudColors.surface
                  : HudColors.todo.withValues(alpha: 0.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(HudRadii.panel),
          border: Border.all(
            color: todo.completed
                ? HudColors.border
                : HudColors.todo.withValues(alpha: 0.42),
            width: todo.completed ? 1.0 : 1.1,
          ),
          boxShadow: todo.completed
              ? HudElevation.card(HudColors.border)
              : HudElevation.glow(HudColors.todo),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(HudRadii.panel),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              HudSpacing.xl,
              HudSpacing.lg,
              HudSpacing.md,
              HudSpacing.lg,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: onToggle,
                  icon: Icon(
                    todo.completed
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: todo.completed
                        ? HudColors.completed
                        : HudColors.todo,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                ),
                const SizedBox(width: HudSpacing.sm),
                Expanded(
                  child: Text(
                    todo.title,
                    style: HudText.title.copyWith(
                      fontSize: 14.5,
                      decoration: todo.completed
                          ? TextDecoration.lineThrough
                          : null,
                      color: todo.completed
                          ? HudColors.textTertiary
                          : HudColors.textPrimary,
                    ),
                  ),
                ),
                if (todo.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: HudSpacing.sm),
                    child: Icon(
                      Icons.notes_rounded,
                      size: 14,
                      color: HudColors.textTertiary,
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

class _EmptyTodos extends StatelessWidget {
  const _EmptyTodos({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.checklist_rounded,
            size: 40,
            color: HudColors.textTertiary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: HudSpacing.lg),
          Text('暂无待办', style: HudText.label),
          const SizedBox(height: HudSpacing.sm),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('添加一个'),
          ),
        ],
      ),
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
      backgroundColor: HudColors.surfaceRaised,
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
