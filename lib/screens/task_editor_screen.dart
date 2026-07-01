import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/message_guard.dart';

/// Google Calendar colorId → 表示色のマッピング（API v3 の固定パレット）。
const Map<String, Color> kGoogleEventColors = {
  '1': Color(0xFF7986CB), // Lavender
  '2': Color(0xFF33B679), // Sage
  '3': Color(0xFF8E24AA), // Grape
  '4': Color(0xFFE67C73), // Flamingo
  '5': Color(0xFFF6BF26), // Banana
  '6': Color(0xFFF4511E), // Tangerine
  '7': Color(0xFF039BE5), // Peacock
  '8': Color(0xFF616161), // Graphite
  '9': Color(0xFF3F51B5), // Blueberry
  '10': Color(0xFF0B8043), // Basil
  '11': Color(0xFFD50000), // Tomato
};

enum TaskEditorMode { create, edit }

/// 繰り返し頻度のプリセット。RRULE 文字列にマッピングして保存する。
enum RecurrencePreset { none, daily, weekly, monthly, yearly }

String? _buildRrule(RecurrencePreset p) {
  switch (p) {
    case RecurrencePreset.none:
      return null;
    case RecurrencePreset.daily:
      return 'RRULE:FREQ=DAILY';
    case RecurrencePreset.weekly:
      return 'RRULE:FREQ=WEEKLY';
    case RecurrencePreset.monthly:
      return 'RRULE:FREQ=MONTHLY';
    case RecurrencePreset.yearly:
      return 'RRULE:FREQ=YEARLY';
  }
}

RecurrencePreset _parseRrule(List<String>? recurrence) {
  if (recurrence == null || recurrence.isEmpty) return RecurrencePreset.none;
  final rrule = recurrence.firstWhere(
    (s) => s.startsWith('RRULE:'),
    orElse: () => '',
  );
  if (rrule.contains('FREQ=DAILY')) return RecurrencePreset.daily;
  if (rrule.contains('FREQ=WEEKLY')) return RecurrencePreset.weekly;
  if (rrule.contains('FREQ=MONTHLY')) return RecurrencePreset.monthly;
  if (rrule.contains('FREQ=YEARLY')) return RecurrencePreset.yearly;
  return RecurrencePreset.none;
}

String _recurrenceLabel(RecurrencePreset p) {
  switch (p) {
    case RecurrencePreset.none:
      return '繰り返さない';
    case RecurrencePreset.daily:
      return '毎日';
    case RecurrencePreset.weekly:
      return '毎週';
    case RecurrencePreset.monthly:
      return '毎月';
    case RecurrencePreset.yearly:
      return '毎年';
  }
}

/// 新規作成 / 既存編集の共通エディタ画面。
/// 既存編集時は [initial] を渡す。複製時は [initial] + [mode = create] で呼ぶ。
class TaskEditorScreen extends ConsumerStatefulWidget {
  const TaskEditorScreen({
    super.key,
    required this.mode,
    this.initial,
    this.initialStart,
  });

  final TaskEditorMode mode;
  final CalendarTask? initial;
  final DateTime? initialStart;

  @override
  ConsumerState<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends ConsumerState<TaskEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  late DateTime _start;
  late DateTime _end;
  bool _isAllDay = false;
  String? _selectedColorId;
  RecurrencePreset _recurrence = RecurrencePreset.none;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _titleCtrl.text = initial.title;
      _locationCtrl.text = initial.location ?? '';
      _descriptionCtrl.text = initial.description ?? '';
      _isAllDay = initial.isAllDay;
      _selectedColorId = initial.colorId;
      _recurrence = _parseRrule(initial.recurrence);
      // 複製時は initialStart が渡され、所要時間は元タスクから引き継ぐ。
      if (widget.initialStart != null && widget.mode == TaskEditorMode.create) {
        final duration = (initial.end != null && initial.start != null)
            ? initial.end!.difference(initial.start!)
            : const Duration(hours: 1);
        _start = widget.initialStart!;
        _end = _start.add(duration);
      } else {
        _start = initial.start ?? DateTime.now();
        _end = initial.end ?? _start.add(const Duration(hours: 1));
      }
    } else {
      final base = widget.initialStart ?? _roundedNextHour(DateTime.now());
      _start = base;
      _end = base.add(const Duration(hours: 1));
    }
  }

  DateTime _roundedNextHour(DateTime d) {
    final rounded = DateTime(d.year, d.month, d.day, d.hour + 1);
    return rounded;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final base = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(base.year - 5),
      lastDate: DateTime(base.year + 5),
    );
    if (picked == null) return;
    setState(() {
      final merged = DateTime(
          picked.year, picked.month, picked.day, base.hour, base.minute);
      if (isStart) {
        final shift = merged.difference(_start);
        _start = merged;
        if (_end.isBefore(_start)) {
          _end = _start.add(const Duration(hours: 1));
        } else {
          final shifted = _end.add(shift);
          _end = shifted.isBefore(_start)
              ? _start.add(const Duration(hours: 1))
              : shifted;
        }
      } else {
        _end = merged;
        if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final base = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (picked == null) return;
    setState(() {
      final merged = DateTime(
          base.year, base.month, base.day, picked.hour, picked.minute);
      if (isStart) {
        _start = merged;
        if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
      } else {
        _end = merged;
        if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final vm = ref.read(calendarSyncViewModelProvider.notifier);
    final title = _titleCtrl.text.trim();
    final description = _descriptionCtrl.text.trim();
    final location = _locationCtrl.text.trim();

    final rrule = _buildRrule(_recurrence);
    final recurrence = rrule == null ? null : [rrule];

    bool success;
    if (widget.mode == TaskEditorMode.create) {
      success = await vm.saveNewTask(
        title: title,
        start: _start,
        end: _end,
        isAllDay: _isAllDay,
        description: description.isEmpty ? null : description,
        location: location.isEmpty ? null : location,
        colorId: _selectedColorId,
        recurrence: recurrence,
      );
    } else {
      success = await vm.updateExistingTask(
        original: widget.initial!,
        title: title,
        start: _start,
        end: _end,
        isAllDay: _isAllDay,
        description: description,
        location: location,
        colorId: _selectedColorId,
        recurrence: recurrence ?? const [],
      );
    }
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
    final initial = widget.initial;
    if (initial == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${initial.title}」を削除しますか？'),
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
    final ok = await vm.deleteTask(initial);
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
    final dateFmt = DateFormat('M月d日(E)', 'ja_JP');
    final timeFmt = DateFormat('HH:mm');
    final isEdit = widget.mode == TaskEditorMode.edit;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '予定を編集' : '予定を追加'),
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
                controller: _titleCtrl,
              autofocus: !isEdit,
              decoration: const InputDecoration(
                labelText: 'タイトル',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'タイトルを入力してください' : null,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('終日'),
              value: _isAllDay,
              onChanged: (v) => setState(() => _isAllDay = v),
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('開始'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => _pickDate(isStart: true),
                    child: Text(dateFmt.format(_start)),
                  ),
                  if (!_isAllDay)
                    TextButton(
                      onPressed: () => _pickTime(isStart: true),
                      child: Text(timeFmt.format(_start)),
                    ),
                ],
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('終了'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => _pickDate(isStart: false),
                    child: Text(dateFmt.format(_end)),
                  ),
                  if (!_isAllDay)
                    TextButton(
                      onPressed: () => _pickTime(isStart: false),
                      child: Text(timeFmt.format(_end)),
                    ),
                ],
              ),
            ),
            const Divider(),
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
                            child: Text(_recurrenceLabel(p)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _recurrence = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (isEdit)
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
