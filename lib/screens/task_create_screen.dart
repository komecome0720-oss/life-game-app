import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/utils/recurrence_preset.dart';
import 'package:task_manager/widgets/message_guard.dart';
import 'package:task_manager/widgets/prediction_chip_settings_dialog.dart';
import 'package:task_manager/widgets/prediction_chip_sheet.dart';
import 'package:task_manager/widgets/task_detail/quadrant_selector.dart';

/// 新しい「フル作成画面」。
/// FAB「＋」（新規作成）と詳細シートの「複製」から呼ばれる。
/// [QuickCreateSheet] のデザイン言語（アイコン付き見出し・チップ主体UI）を踏襲するが、
/// フルページで タイトル／領域／終日／開始/終了／場所／説明／繰り返し を扱う。
/// 色選択UIは置かない（新規作成時は常に colorId=null）。
class TaskCreateScreen extends ConsumerStatefulWidget {
  const TaskCreateScreen({super.key, this.initial, this.initialStart});

  /// 複製元タスク。非nullなら複製（タイトル・領域・場所・説明・繰り返しを引き継ぐ。
  /// 色は引き継がない）。
  final CalendarTask? initial;

  /// 開始時刻の初期値。複製時は呼び出し元が `task.end` を渡す。
  final DateTime? initialStart;

  @override
  ConsumerState<TaskCreateScreen> createState() => _TaskCreateScreenState();
}

class _TaskCreateScreenState extends ConsumerState<TaskCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  late DateTime _start;
  bool _isAllDay = false;
  Quadrant _selectedQuadrant = Quadrant.urgentImportant;
  RecurrencePreset _recurrence = RecurrencePreset.none;
  int? _durationMinutes;
  DateTime? _endDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _titleCtrl.text = initial.title;
      _locationCtrl.text = initial.location ?? '';
      _descriptionCtrl.text = initial.description ?? '';
      _selectedQuadrant =
          QuadrantX.from(urgency: initial.urgency, importance: initial.importance);
      _recurrence = parseRrule(initial.recurrence);
      _isAllDay = initial.isAllDay;
      _start = widget.initialStart ?? initial.start ?? _roundedNextHour(DateTime.now());
      if (initial.end != null && initial.start != null) {
        _durationMinutes = initial.end!.difference(initial.start!).inMinutes;
      }
      if (_isAllDay) {
        _endDate = initial.end ?? _start;
      }
    } else {
      _start = widget.initialStart ?? _roundedNextHour(DateTime.now());
    }
  }

  DateTime _roundedNextHour(DateTime d) {
    return DateTime(d.year, d.month, d.day, d.hour + 1);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(_start.year - 5),
      lastDate: DateTime(_start.year + 5),
    );
    if (picked == null) return;
    setState(() {
      _start = DateTime(
          picked.year, picked.month, picked.day, _start.hour, _start.minute);
      if (_isAllDay && _endDate != null && _endDate!.isBefore(_start)) {
        _endDate = _start;
      }
    });
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (picked == null) return;
    setState(() {
      _start = DateTime(_start.year, _start.month, _start.day, picked.hour,
          picked.minute);
    });
  }

  Future<void> _pickEndDate() async {
    final base = _endDate ?? _start;
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(_start.year - 5),
      lastDate: DateTime(_start.year + 5),
    );
    if (picked == null) return;
    setState(() {
      _endDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _openFreeInput() async {
    final minutes = await showPredictionFreeInputDialog(context);
    if (minutes != null && mounted) {
      setState(() => _durationMinutes = minutes);
    }
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const PredictionChipSettingsDialog(),
    );
  }

  bool get _canSave => _titleCtrl.text.trim().isNotEmpty &&
      (_isAllDay || _durationMinutes != null);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isAllDay && _durationMinutes == null) return;

    setState(() => _saving = true);
    final vm = ref.read(calendarSyncViewModelProvider.notifier);
    final title = _titleCtrl.text.trim();
    final description = _descriptionCtrl.text.trim();
    final location = _locationCtrl.text.trim();

    final rrule = buildRrule(_recurrence);
    final recurrence = rrule == null ? null : [rrule];

    final DateTime end;
    if (_isAllDay) {
      end = _endDate ?? _start;
    } else {
      end = _start.add(Duration(minutes: _durationMinutes!));
    }

    final success = await vm.saveNewTask(
      title: title,
      start: _start,
      end: end,
      isAllDay: _isAllDay,
      description: description.isEmpty ? null : description,
      location: location.isEmpty ? null : location,
      colorId: null,
      recurrence: recurrence,
      urgency: _selectedQuadrant.urgency,
      importance: _selectedQuadrant.importance,
      estimatedMinutes: _isAllDay ? null : _durationMinutes,
      predictionDeclared: !_isAllDay,
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

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('M月d日(E)', 'ja_JP');
    final timeFmt = DateFormat('HH:mm');
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final presets = ref.watch(
      userSettingsProvider.select((s) => s.settings.predictionChipMinutes),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('予定を追加'),
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
              onPressed: _canSave ? _save : null,
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
              Row(
                children: [
                  Icon(Icons.event, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '予定を追加',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleCtrl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'タイトル',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'タイトルを入力してください' : null,
              ),
              const SizedBox(height: 14),
              Text('領域', style: text.labelMedium),
              const SizedBox(height: 8),
              QuadrantSelector(
                selected: _selectedQuadrant,
                onSelect: (q) => setState(() => _selectedQuadrant = q),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('終日'),
                value: _isAllDay,
                onChanged: (v) => setState(() {
                  _isAllDay = v;
                  if (v) {
                    _endDate ??= _start;
                  }
                }),
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
                      onPressed: _pickStartDate,
                      child: Text(dateFmt.format(_start)),
                    ),
                    if (!_isAllDay)
                      TextButton(
                        onPressed: _pickStartTime,
                        child: Text(timeFmt.format(_start)),
                      ),
                  ],
                ),
              ),
              if (_isAllDay)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('終了'),
                  trailing: TextButton(
                    onPressed: _pickEndDate,
                    child: Text(dateFmt.format(_endDate ?? _start)),
                  ),
                )
              else ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '予測時間（終了時刻はこれで決まります）',
                        style: text.labelMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: 'プリセットを編集',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in presets)
                      ChoiceChip(
                        label: Text(formatPredictionMinutes(m)),
                        selected: _durationMinutes == m,
                        onSelected: (_) => setState(() => _durationMinutes = m),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.edit, size: 18),
                      label: Text(
                        _durationMinutes != null &&
                                !presets.contains(_durationMinutes)
                            ? formatPredictionMinutes(_durationMinutes!)
                            : '自由入力',
                      ),
                      onPressed: _openFreeInput,
                    ),
                  ],
                ),
              ],
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
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
