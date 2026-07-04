/// 週の開始（指定曜日 0:00）を返す。[startDay] は ISO 形式で 1=月…7=日。
DateTime startOfWeek(DateTime date, int startDay) {
  final d = DateTime(date.year, date.month, date.day);
  final weekday = d.weekday; // 1=Mon ... 7=Sun
  final diff = (weekday - startDay + 7) % 7;
  return d.subtract(Duration(days: diff));
}

/// 月曜を週開始とする慣用ショートカット。
DateTime startOfWeekMonday(DateTime date) => startOfWeek(date, DateTime.monday);
