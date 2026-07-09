import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/health/model/health_category.dart';
import 'package:task_manager/features/health/model/health_log.dart';
import 'package:task_manager/features/health/model/health_scoring.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';

void main() {
  group('HealthScoring', () {
    test('scores regular categories from 0 to the goal', () {
      expect(HealthScoring.level(0, 300), 0);
      expect(HealthScoring.level(150, 300), 5);
      expect(HealthScoring.level(300, 300), 10);
      expect(HealthScoring.level(450, 300), 10);

      expect(HealthScoring.score(0, 300, 3), 0);
      expect(HealthScoring.score(150, 300, 3), 15);
      expect(HealthScoring.score(300, 300, 3), 30);
      expect(HealthScoring.score(450, 300, 3), 30);
    });

    test('maxActiveScore は瞑想ON=100 / OFF=80', () {
      expect(HealthScoring.maxActiveScore(meditationEnabled: true), 100);
      expect(HealthScoring.maxActiveScore(meditationEnabled: false), 80);
    });

    test('achievementRatio は totalScore/maxActiveScore を0〜1でクランプ', () {
      expect(HealthScoring.achievementRatio(0, 100), 0.0);
      expect(HealthScoring.achievementRatio(40, 100), 0.4);
      expect(HealthScoring.achievementRatio(100, 100), 1.0);
      expect(HealthScoring.achievementRatio(120, 100), 1.0); // クランプ
      expect(HealthScoring.achievementRatio(80, 80), 1.0);
      expect(HealthScoring.achievementRatio(0, 0), 0.0); // maxActiveScore<=0
    });

    // 線形・40%ゲート。p<0.40 は没収(0)、p>=0.40 は round(cap * p)。
    test('earningsForRatio は40%ゲートで線形按分・四捨五入', () {
      // p<0.40 は没収
      expect(HealthScoring.earningsForRatio(ratio: 0.39, dailyCapYen: 300), 0);
      expect(HealthScoring.earningsForRatio(ratio: 0.0, dailyCapYen: 300), 0);

      // p>=0.40 は round(cap*p)
      expect(
        HealthScoring.earningsForRatio(ratio: 0.40, dailyCapYen: 300),
        120,
      ); // round(300*0.4)=120
      expect(
        HealthScoring.earningsForRatio(ratio: 1.0, dailyCapYen: 300),
        300,
      );

      // dailyCapYen<=0 は0
      expect(HealthScoring.earningsForRatio(ratio: 1.0, dailyCapYen: 0), 0);
    });

    test('scores sleep from three hours to the goal', () {
      const baseline = HealthCategoryX.sleepBaselineMinutes;
      expect(HealthScoring.level(180, 420, baseline: baseline), 0);
      expect(HealthScoring.level(300, 420, baseline: baseline), 5);
      expect(HealthScoring.level(420, 420, baseline: baseline), 10);
      expect(HealthScoring.level(120, 420, baseline: baseline), 0);
      expect(HealthScoring.level(480, 420, baseline: baseline), 10);

      expect(HealthScoring.score(180, 420, 3, baseline: baseline), 0);
      expect(HealthScoring.score(300, 420, 3, baseline: baseline), 15);
      expect(HealthScoring.score(420, 420, 3, baseline: baseline), 30);
      expect(HealthScoring.score(120, 420, 3, baseline: baseline), 0);
      expect(HealthScoring.score(480, 420, 3, baseline: baseline), 30);
    });
  });

  group('HealthCategory scale conversion', () {
    test('converts meal levels to goal-linked values', () {
      const settings = UserSettings(mealGoalGrams: 300);

      expect(HealthCategory.meal.valueForLevel(0, settings), 0);
      expect(HealthCategory.meal.valueForLevel(5, settings), 150);
      expect(HealthCategory.meal.valueForLevel(10, settings), 300);
      expect(
        HealthCategory.meal.valueForLevel(
          10,
          const UserSettings(mealGoalGrams: 333),
        ),
        333,
      );
    });

    test('converts sleep levels from the three-hour baseline', () {
      const settings = UserSettings(sleepGoalHours: 7);

      expect(HealthCategory.sleep.valueForLevel(0, settings), 180);
      expect(HealthCategory.sleep.valueForLevel(5, settings), 300);
      expect(HealthCategory.sleep.valueForLevel(10, settings), 420);
    });

    test('keeps small goals evenly divisible with decimal values', () {
      const settings = UserSettings(exerciseGoalMinutes: 7);

      expect(
        HealthCategory.exercise.valueForLevel(1, settings),
        closeTo(0.7, 0.0001),
      );
      expect(
        HealthCategory.exercise.valueForLevel(5, settings),
        closeTo(3.5, 0.0001),
      );
      expect(HealthCategory.exercise.valueForLevel(10, settings), 7);
    });

    test(
      'levels existing over-goal values as full completion without mutating them',
      () {
        const settings = UserSettings(mealGoalGrams: 100);
        const log = HealthLog(dateKey: '2026-06-09', mealGrams: 300);

        expect(HealthCategory.meal.level(log, settings), 10);
        expect(HealthCategory.meal.levelForValue(log.mealGrams, settings), 10);
        expect(log.mealGrams, 300);
      },
    );

    test('validates category goals before saving settings', () {
      expect(HealthCategory.meal.validateGoal(const UserSettings()), isNotNull);
      expect(
        HealthCategory.exercise.validateGoal(
          const UserSettings(exerciseGoalMinutes: 1),
        ),
        isNull,
      );
      expect(
        HealthCategory.sleep.validateGoal(
          const UserSettings(sleepGoalHours: 3),
        ),
        isNotNull,
      );
      expect(
        HealthCategory.sleep.validateGoal(
          const UserSettings(sleepGoalHours: 3, sleepGoalMinutesExtra: 1),
        ),
        isNull,
      );
    });

    test('formats whole values without trailing decimal zero', () {
      expect(HealthCategory.meal.formatValue(175), '175 g');
      expect(HealthCategory.exercise.formatValue(10), '10 分');
      expect(HealthCategory.meditation.formatValue(0.7), '0.7 分');
      expect(HealthCategory.sleep.formatValue(360), '6 時間');
      expect(HealthCategory.sleep.formatValue(369), '6時間9分');
      expect(HealthCategory.sleep.formatValue(369.5), '6時間9.5分');
    });
  });
}
