import 'package:cloud_firestore/cloud_firestore.dart';

enum EarningsPeriod { week, month, year }

extension EarningsPeriodX on EarningsPeriod {
  int get windowDays => switch (this) {
    EarningsPeriod.week => 7,
    EarningsPeriod.month => 30,
    EarningsPeriod.year => 365,
  };

  String get label => switch (this) {
    EarningsPeriod.week => '1週間',
    EarningsPeriod.month => '30日',
    EarningsPeriod.year => '年',
  };
}

/// `users/{uid}/daily_earnings/{YYYY-MM-DD}` の1日分。
/// 値はクランプ前の生ネット値（保存時は `FieldValue.increment` の都合上クランプしない）。
class DailyEarning {
  const DailyEarning({
    required this.date,
    required this.taskYen,
    required this.healthYen,
    required this.manualYen,
  });

  /// ローカル日付の午前0時（時刻情報なし）。
  final DateTime date;
  final int taskYen;
  final int healthYen;
  final int manualYen;

  int get clampedTaskYen => taskYen < 0 ? 0 : taskYen;
  int get clampedHealthYen => healthYen < 0 ? 0 : healthYen;
  int get clampedManualYen => manualYen < 0 ? 0 : manualYen;
  int get clampedTotalYen =>
      clampedTaskYen + clampedHealthYen + clampedManualYen;

  factory DailyEarning.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return DailyEarning(
      date: parseDateKey(doc.id),
      taskYen: (data['taskYen'] as num?)?.toInt() ?? 0,
      healthYen: (data['healthYen'] as num?)?.toInt() ?? 0,
      manualYen: (data['manualYen'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 累積折れ線の1点（クランプ済み日次獲得額の累積）。
class CumulativePoint {
  const CumulativePoint(this.date, this.cumulativeYen);

  final DateTime date;
  final int cumulativeYen;
}

/// 積み上げ棒の1本（週/月は日次、年は月次に集計される）。
class DailyBarBucket {
  const DailyBarBucket({
    required this.label,
    required this.taskYen,
    required this.healthYen,
    required this.manualYen,
  });

  /// 週/月は当日の日付、年はその月の1日。
  final DateTime label;
  final int taskYen;
  final int healthYen;
  final int manualYen;

  int get total => taskYen + healthYen + manualYen;
}

class EarningsWindowData {
  const EarningsWindowData({
    required this.cumulativePoints,
    required this.totalYen,
    required this.bars,
    required this.period,
  });

  final List<CumulativePoint> cumulativePoints;

  /// 全期間の通算獲得額（カード右上の表示と一致）。
  final int totalYen;
  final List<DailyBarBucket> bars;
  final EarningsPeriod period;
}

DateTime parseDateKey(String key) {
  final parts = key.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

String formatDateKey(DateTime date) {
  String pad2(int v) => v.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-${pad2(date.month)}-${pad2(date.day)}';
}

DateTime _localMidnight(DateTime d) => DateTime(d.year, d.month, d.day);

int totalClampedEarnings(List<DailyEarning> allEarnings) {
  return allEarnings.fold<int>(0, (total, e) => total + e.clampedTotalYen);
}

/// [today] を含む過去 [period.windowDays] 日分の累積折れ線を構築する。
/// 起点（[today]-windowDays の前日まで）の累積値から始まり、
/// データのない日は前日値を横ばいで引き継ぐ。
List<CumulativePoint> buildCumulativeWindow({
  required List<DailyEarning> allEarnings,
  required DateTime today,
  required EarningsPeriod period,
}) {
  final todayMidnight = _localMidnight(today);
  final byKey = <String, DailyEarning>{
    for (final e in allEarnings) formatDateKey(_localMidnight(e.date)): e,
  };
  final sortedKeys = byKey.keys.toList()..sort();

  final cumulativeByKey = <String, int>{};
  var running = 0;
  for (final key in sortedKeys) {
    running += byKey[key]!.clampedTotalYen;
    cumulativeByKey[key] = running;
  }

  final windowStart = todayMidnight.subtract(
    Duration(days: period.windowDays - 1),
  );
  final dayBeforeStart = windowStart.subtract(const Duration(days: 1));

  var startValue = 0;
  for (final key in sortedKeys) {
    final date = parseDateKey(key);
    if (!date.isAfter(dayBeforeStart)) {
      startValue = cumulativeByKey[key]!;
    } else {
      break;
    }
  }

  final points = <CumulativePoint>[];
  var carry = startValue;
  for (
    var d = windowStart;
    !d.isAfter(todayMidnight);
    d = d.add(const Duration(days: 1))
  ) {
    final key = formatDateKey(d);
    final value = cumulativeByKey[key];
    if (value != null) carry = value;
    points.add(CumulativePoint(d, carry));
  }
  return points;
}

/// 週/月は日次、年は月次（過去12ヶ月・当月含む）で積み上げ棒データを構築する。
/// データのない日/月も 0 として含める。
List<DailyBarBucket> buildDailyBars({
  required List<DailyEarning> allEarnings,
  required DateTime today,
  required EarningsPeriod period,
}) {
  final todayMidnight = _localMidnight(today);

  if (period == EarningsPeriod.year) {
    final months = [
      for (var i = 11; i >= 0; i--) DateTime(todayMidnight.year, todayMidnight.month - i, 1),
    ];
    return months.map((month) {
      var task = 0, health = 0, manual = 0;
      for (final e in allEarnings) {
        if (e.date.year == month.year && e.date.month == month.month) {
          task += e.clampedTaskYen;
          health += e.clampedHealthYen;
          manual += e.clampedManualYen;
        }
      }
      return DailyBarBucket(
        label: month,
        taskYen: task,
        healthYen: health,
        manualYen: manual,
      );
    }).toList();
  }

  final byKey = <String, DailyEarning>{
    for (final e in allEarnings) formatDateKey(_localMidnight(e.date)): e,
  };
  final windowStart = todayMidnight.subtract(
    Duration(days: period.windowDays - 1),
  );
  final buckets = <DailyBarBucket>[];
  for (
    var d = windowStart;
    !d.isAfter(todayMidnight);
    d = d.add(const Duration(days: 1))
  ) {
    final e = byKey[formatDateKey(d)];
    buckets.add(
      DailyBarBucket(
        label: d,
        taskYen: e?.clampedTaskYen ?? 0,
        healthYen: e?.clampedHealthYen ?? 0,
        manualYen: e?.clampedManualYen ?? 0,
      ),
    );
  }
  return buckets;
}

EarningsWindowData buildEarningsWindowData({
  required List<DailyEarning> allEarnings,
  required DateTime today,
  required EarningsPeriod period,
}) {
  return EarningsWindowData(
    cumulativePoints: buildCumulativeWindow(
      allEarnings: allEarnings,
      today: today,
      period: period,
    ),
    totalYen: totalClampedEarnings(allEarnings),
    bars: buildDailyBars(allEarnings: allEarnings, today: today, period: period),
    period: period,
  );
}
