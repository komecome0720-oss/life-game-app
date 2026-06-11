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
