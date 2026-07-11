/// 繰り返し頻度のプリセット。RRULE 文字列にマッピングして保存する。
/// `task_create_screen.dart`（新規作成）と `task_editor_screen.dart`
/// （`TaskDetailEditScreen`、詳細編集）の双方から共通利用する。
enum RecurrencePreset { none, daily, weekly, monthly, yearly }

String? buildRrule(RecurrencePreset p) {
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

RecurrencePreset parseRrule(List<String>? recurrence) {
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

String recurrenceLabel(RecurrencePreset p) {
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
