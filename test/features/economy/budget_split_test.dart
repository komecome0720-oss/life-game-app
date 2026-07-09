import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/economy/model/budget_split.dart';

void main() {
  group('kTaskBudgetRatio / kHealthBudgetRatio', () {
    test('タスク70%・健康30%で合計1.0', () {
      expect(kTaskBudgetRatio, 0.70);
      expect(kHealthBudgetRatio, 0.30);
      expect(kTaskBudgetRatio + kHealthBudgetRatio, closeTo(1.0, 1e-9));
    });
  });

  group('healthDailyCap 例', () {
    test('monthlyBudget=30000円 → 健康月間プール9000円 → 日割り300円', () {
      const monthlyBudget = 30000.0;
      final healthMonthlyPool = monthlyBudget * kHealthBudgetRatio;
      expect(healthMonthlyPool, 9000.0);
      final dailyCap = (healthMonthlyPool / kHealthCapDays).round();
      expect(dailyCap, 300);
    });
  });

  group('taskHourlyRate', () {
    test('hourlyRate × 0.70 になる', () {
      const hourlyRate = 1000.0;
      expect(hourlyRate * kTaskBudgetRatio, 700.0);
    });
  });

  group('streakTitleForCount', () {
    test('節目日数で称号が返る', () {
      expect(streakTitleForCount(3), '習慣の芽');
      expect(streakTitleForCount(7), '一週間の勇者');
      expect(streakTitleForCount(14), '二週間の達人');
      expect(streakTitleForCount(30), '一ヶ月の賢者');
      expect(streakTitleForCount(60), '不屈の求道者');
      expect(streakTitleForCount(100), '健康の化身');
    });

    test('節目でない日数はnull', () {
      expect(streakTitleForCount(1), isNull);
      expect(streakTitleForCount(4), isNull);
      expect(streakTitleForCount(101), isNull);
    });
  });

  group('kHealthGaugeRatios / freeze定数', () {
    test('ゲージ線は40/60/80%', () {
      expect(kHealthGaugeRatios, [0.40, 0.60, 0.80]);
    });

    test('フリーズ月次付与2・上限5', () {
      expect(kFreezeMonthlyGrant, 2);
      expect(kFreezeMax, 5);
    });
  });
}
