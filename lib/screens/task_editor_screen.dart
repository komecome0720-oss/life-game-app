import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/utils/google_event_colors.dart';
import 'package:task_manager/utils/recurrence_preset.dart';
import 'package:task_manager/widgets/message_guard.dart';

/// 予定の詳細画面。タイトル・領域・終日・開始/終了はカレンダータップ画面側で
/// 既に編集可能なため、ここでは重複させず「場所／説明／繰り返し／色」のみ編集する。
class TaskDetailEditScreen extends ConsumerStatefulWidget {
  const TaskDetailEditScreen({super.key, required this.task});

  final CalendarTask task;

  @override
  ConsumerState<TaskDetailEditScreen> createState() =>
      _TaskDetailEditScreenState();
}

class _TaskDetailEditScreenState extends ConsumerState<TaskDetailEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _locationCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  String? _selectedColorId;
  RecurrencePreset _recurrence = RecurrencePreset.none;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _locationCtrl.text = task.location ?? '';
    _descriptionCtrl.text = task.description ?? '';
    _selectedColorId = task.colorId;
    _recurrence = parseRrule(task.recurrence);
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final vm = ref.read(calendarSyncViewModelProvider.notifier);
    final description = _descriptionCtrl.text.trim();
    final location = _locationCtrl.text.trim();

    final rrule = buildRrule(_recurrence);
    final recurrence = rrule == null ? null : [rrule];

    // widget.task.start!/end! の強制アンラップについて: この画面は
    // home_screen.dart の _openTask（カレンダー表示中＝週表示に出現するタスク）
    // 経由でのみ開かれ、isTodo=true（start/end が null になりうる ToDo 専用タスク）は
    // 週表示に出現しないため実質的に安全。
    final success = await vm.updateExistingTask(
      original: widget.task,
      title: widget.task.title,
      start: widget.task.start!,
      end: widget.task.end!,
      isAllDay: widget.task.isAllDay,
      description: description,
      location: location,
      colorId: _selectedColorId,
      recurrence: recurrence ?? const [],
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final msg = ref.read(calendarSyncViewModelProvider).errorMessage;
      showAppSnackBar(
        context,
        SnackBar(content: Text(msg ?? '保存に失敗しました')),
      );
      ref.read(calendarSyncViewModelProvider.notifier).clearError();
    }
  }

  Future<void> _delete() async {
    final task = widget.task;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${task.title}」を削除しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final vm = ref.read(calendarSyncViewModelProvider.notifier);
    final ok = await vm.deleteTask(task);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      final msg = ref.read(calendarSyncViewModelProvider).errorMessage;
      showAppSnackBar(
        context,
        SnackBar(content: Text(msg ?? '削除に失敗しました')),
      );
      vm.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('予定の詳細'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('保存',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: MessageGuard(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _locationCtrl,
                decoration: const InputDecoration(
                  labelText: '場所',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '説明',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: '色',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ColorChip(
                      color: null,
                      selected: _selectedColorId == null,
                      onTap: () => setState(() => _selectedColorId = null),
                    ),
                    ...kGoogleEventColors.entries.map((e) => _ColorChip(
                          color: e.value,
                          selected: _selectedColorId == e.key,
                          onTap: () =>
                              setState(() => _selectedColorId = e.key),
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: '繰り返し',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<RecurrencePreset>(
                    value: _recurrence,
                    isExpanded: true,
                    items: RecurrencePreset.values
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(recurrenceLabel(p)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _recurrence = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _saving ? null : _delete,
                icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                label: Text('削除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color ?? scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        child: color == null
            ? Icon(Icons.block, size: 16, color: scheme.onSurfaceVariant)
            : null,
      ),
    );
  }
}
