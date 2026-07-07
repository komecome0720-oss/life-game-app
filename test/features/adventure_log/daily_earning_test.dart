import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/adventure_log/model/daily_earning.dart';

void main() {
  group('DailyEarning clamp', () {
    test('負の値は0にクランプされる', () {
      final earning = DailyEarning(
        date: DateTime(2026, 7, 5),
        taskYen: -500,
        healthYen: 200,
        manualYen: -100,
      );
      expect(earning.clampedTaskYen, 0);
      expect(earning.clampedHealthYen, 200);
      expect(earning.clampedManualYen, 0);
      expect(earning.clampedTotalYen, 200);
    });
  });

  group('buildCumulativeWindow', () {
    test('日次クランプ値の累積和になり、データのない日は横ばい', () {
      final today = DateTime(2026, 7, 5);
      final earnings = [
        DailyEarning(
          date: DateTime(2026, 7, 3),
          taskYen: 1000,
          healthYen: 0,
          manualYen: 0,
        ),
        DailyEarning(
          date: DateTime(2026, 7, 5),
          taskYen: -200, // 取り消しで相殺、クランプで0
          healthYen: 300,
          manualYen: 0,
        ),
      ];

      final points = buildCumulativeWindow(
        allEarnings: earnings,
        today: today,
        period: EarningsPeriod.week,
      );

      expect(points.length, 7);
      expect(points.first.date, DateTime(2026, 6, 29));
      expect(points.first.cumulativeYen, 0);
      // 7/3 の 1000 が積まれ、7/4 は横ばい
      final jul3 = points.firstWhere((p) => p.date == DateTime(2026, 7, 3));
      final jul4 = points.firstWhere((p) => p.date == DateTime(2026, 7, 4));
      expect(jul3.cumulativeYen, 1000);
      expect(jul4.cumulativeYen, 1000);
      // 7/5: task=-200→クランプ0, health=300 → +300
      final jul5 = points.firstWhere((p) => p.date == DateTime(2026, 7, 5));
      expect(jul5.cumulativeYen, 1300);
    });

    test('起点は窓開始日の前日までの累積値', () {
      final today = DateTime(2026, 7, 10);
      final earnings = [
        DailyEarning(
          date: DateTime(2026, 6, 1),
          taskYen: 5000,
          healthYen: 0,
          manualYen: 0,
        ),
      ];

      final points = buildCumulativeWindow(
        allEarnings: earnings,
        today: today,
        period: EarningsPeriod.week,
      );

      expect(points.every((p) => p.cumulativeYen == 5000), isTrue);
    });
  });

  group('totalClampedEarnings', () {
    test('全期間のクランプ後合計を返す', () {
      final earnings = [
        DailyEarning(
          date: DateTime(2026, 1, 1),
          taskYen: 1000,
          healthYen: -500,
          manualYen: 0,
        ),
        DailyEarning(
          date: DateTime(2026, 1, 2),
          taskYen: 200,
          healthYen: 0,
          manualYen: 100,
        ),
      ];
      expect(totalClampedEarnings(earnings), 1300);
    });
  });

  group('buildDailyBars', () {
    test('週/月は日次バケットになる', () {
      final today = DateTime(2026, 7, 5);
      final earnings = [
        DailyEarning(
          date: DateTime(2026, 7, 5),
          taskYen: 100,
          healthYen: 50,
          manualYen: -10,
        ),
      ];
      final bars = buildDailyBars(
        allEarnings: earnings,
        today: today,
        period: EarningsPeriod.week,
      );
      expect(bars.length, 7);
      final last = bars.last;
      expect(last.label, DateTime(2026, 7, 5));
      expect(last.taskYen, 100);
      expect(last.healthYen, 50);
      expect(last.manualYen, 0); // クランプ
    });

    test('年は月次12本に集計される', () {
      final today = DateTime(2026, 7, 5);
      final earnings = [
        DailyEarning(
          date: DateTime(2026, 7, 1),
          taskYen: 100,
          healthYen: 0,
          manualYen: 0,
        ),
        DailyEarning(
          date: DateTime(2026, 6, 15),
          taskYen: 200,
          healthYen: 0,
          manualYen: 0,
        ),
        DailyEarning(
          date: DateTime(2025, 6, 15),
          taskYen: 9999,
          healthYen: 0,
          manualYen: 0,
        ), // 期間外（13ヶ月前）
      ];
      final bars = buildDailyBars(
        allEarnings: earnings,
        today: today,
        period: EarningsPeriod.year,
      );
      expect(bars.length, 12);
      expect(bars.last.label, DateTime(2026, 7, 1));
      expect(bars.last.taskYen, 100);
      final juneBar = bars.firstWhere(
        (b) => b.label == DateTime(2026, 6, 1),
      );
      expect(juneBar.taskYen, 200);
      expect(bars.first.label, DateTime(2025, 8, 1));
    });
  });
}
