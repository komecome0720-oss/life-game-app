import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/models/calendar_task.dart';

Future<void> showTodoTaskDetailSheet({
  required BuildContext context,
  required CalendarTask task,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _TodoDetailBody(task: task),
    ),
  );
}

class _TodoDetailBody extends ConsumerStatefulWidget {
  const _TodoDetailBody({required this.task});
  final CalendarTask task;

  @override
  ConsumerState<_TodoDetailBody> createState() => _TodoDetailBodyState();
}

class _TodoDetailBodyState extends ConsumerState<_TodoDetailBody> {
  late TextEditingController _titleCtrl;
  late TextEditingController _noteCtrl;
  late bool _urgency;
  late bool _importance;
  late int _estimatedMinutes;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.task.title);
    _noteCtrl = TextEditingController(text: widget.task.note ?? '');
    _urgency = widget.task.urgency;
    _importance = widget.task.importance;
    _estimatedMinutes = widget.task.estimatedMinutes ?? 30;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final updated = widget.task.copyWith(
      title: title,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      urgency: _urgency,
      importance: _importance,
      estimatedMinutes: _estimatedMinutes,
    );
    await ref.read(todoMatrixViewModelProvider).updateTodo(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${widget.task.title}」を削除しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('削除', style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(todoMatrixViewModelProvider).delete(widget.task.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _adjustMinutes(int delta) {
    setState(() {
      _estimatedMinutes = (_estimatedMinutes + delta).clamp(5, 600);
    });
  }

  String _formatMinutes(int m) {
    if (m < 60) return '$m分';
    if (m % 60 == 0) return '${m ~/ 60}時間';
    return '${m ~/ 60}時間${m % 60}分';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ToDo の編集',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'タイトル',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'メモ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.schedule, color: scheme.onSurfaceVariant, size: 20),
                const SizedBox(width: 8),
                Text('予想所要時間', style: text.labelLarge),
                const Spacer(),
                IconButton.outlined(
                  onPressed: () => _adjustMinutes(-15),
                  icon: const Icon(Icons.remove),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Text(_formatMinutes(_estimatedMinutes),
                    style: text.titleSmall
                        ?.copyWith(fontFeatures: const [
                      FontFeature.tabularFigures(),
                    ])),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: () => _adjustMinutes(15),
                  icon: const Icon(Icons.add),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _urgency,
              onChanged: (v) => setState(() => _urgency = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('緊急'),
              subtitle: const Text('上段に配置されます'),
            ),
            SwitchListTile(
              value: _importance,
              onChanged: (v) => setState(() => _importance = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('重要'),
              subtitle: const Text('右列に配置されます'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _confirmDelete,
                  icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  label: Text('削除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: const Text('保存')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
