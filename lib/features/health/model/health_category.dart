import 'package:flutter/material.dart';
import 'package:task_manager/features/health/model/health_log.dart';
import 'package:task_manager/features/health/model/health_scoring.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';

/// 健康カテゴリ。スライダー仕様・目標取得・表示・採点重みを集約する。
enum HealthCategory { meal, exercise, sleep, meditation }

extension HealthCategoryX on HealthCategory {
  static const double sleepBaselineMinutes = 180;

  String get label => switch (this) {
    HealthCategory.meal => '野菜・果物',
    HealthCategory.exercise => '運動',
    HealthCategory.sleep => '睡眠',
    HealthCategory.meditation => '瞑想',
  };

  IconData get icon => switch (this) {
    HealthCategory.meal => Icons.restaurant,
    HealthCategory.exercise => Icons.directions_run,
    HealthCategory.sleep => Icons.bedtime,
    HealthCategory.meditation => Icons.self_improvement,
  };

  /// 重み（食事・睡眠=3、運動・瞑想=2）
  int get weight => switch (this) {
    HealthCategory.meal => 3,
    HealthCategory.sleep => 3,
    HealthCategory.exercise => 2,
    HealthCategory.meditation => 2,
  };

  int get maxPoints => weight * 10;

  // ── 10段階スケール仕様 ───────────────────────────────────────
  double scaleMin(UserSettings s) => switch (this) {
    HealthCategory.sleep => sleepBaselineMinutes,
    _ => 0,
  };

  double scaleMax(UserSettings s) {
    final goal = goalValue(s).toDouble();
    final min = scaleMin(s);
    return goal < min ? min : goal;
  }

  double baseline(UserSettings s) => scaleMin(s);

  double valueForLevel(num level, UserSettings s) {
    final min = scaleMin(s);
    final max = scaleMax(s);
    if (max <= min) return min;
    final clampedLevel = level.clamp(0, 10).toDouble();
    if (clampedLevel == 0) return min;
    if (clampedLevel == 10) return max;
    return min + (max - min) * clampedLevel / 10;
  }

  double levelForValue(num value, UserSettings s) {
    final min = scaleMin(s);
    final max = scaleMax(s);
    if (max <= min) return 0;
    final clampedValue = value.clamp(min, max).toDouble();
    return (clampedValue - min) / (max - min) * 10;
  }

  double clampValue(num value, UserSettings s) {
    final min = scaleMin(s);
    final max = scaleMax(s);
    return value.clamp(min, max).toDouble();
  }

  String? validateGoal(UserSettings s) {
    final goal = goalValue(s);
    return switch (this) {
      HealthCategory.meal when goal <= 0 => '野菜・果物の目標は0より大きい数で入力してください',
      HealthCategory.exercise when goal <= 0 => '運動の目標は0より大きい数で入力してください',
      HealthCategory.meditation when goal <= 0 => '瞑想の目標は0より大きい数で入力してください',
      HealthCategory.sleep when goal <= sleepBaselineMinutes =>
        '睡眠の目標は3時間より長くしてください',
      _ => null,
    };
  }

  // ── 目標・現在値の取得 ───────────────────────────────────────
  int goalValue(UserSettings s) => switch (this) {
    HealthCategory.meal => s.mealGoalGrams,
    HealthCategory.exercise => s.exerciseGoalMinutes,
    HealthCategory.sleep => s.sleepGoalHours * 60 + s.sleepGoalMinutesExtra,
    HealthCategory.meditation => s.meditationGoalMinutes,
  };

  double currentValue(HealthLog log) => switch (this) {
    HealthCategory.meal => log.mealGrams,
    HealthCategory.exercise => log.exerciseMinutes,
    HealthCategory.sleep => log.sleepMinutes,
    HealthCategory.meditation => log.meditationMinutes,
  };

  /// 重み付き点数（0〜maxPoints）
  int score(HealthLog log) => switch (this) {
    HealthCategory.meal => log.mealScore,
    HealthCategory.exercise => log.exerciseScore,
    HealthCategory.sleep => log.sleepScore,
    HealthCategory.meditation => log.meditationScore,
  };

  /// 0〜10 段階の数値（現在値と目標から直接算出。表示は小数点切り捨て）
  int level(HealthLog log, UserSettings s) => HealthScoring.level(
    currentValue(log),
    goalValue(s),
    baseline: baseline(s),
  );

  // ── 表示整形 ─────────────────────────────────────────────────
  String formatValue(num v) {
    String oneDecimalUnlessWhole(num value) {
      final d = value.toDouble();
      if (d == d.roundToDouble()) return d.toInt().toString();
      return d.toStringAsFixed(1);
    }

    final formatted = oneDecimalUnlessWhole(v);
    switch (this) {
      case HealthCategory.meal:
        return '$formatted g';
      case HealthCategory.exercise:
      case HealthCategory.meditation:
        return '$formatted 分';
      case HealthCategory.sleep:
        final totalMinutes = v.toDouble();
        final h = totalMinutes ~/ 60;
        final m = totalMinutes - h * 60;
        if (m == 0) return '$h 時間';
        return '$h時間${oneDecimalUnlessWhole(m)}分';
    }
  }

  String formatGoal(UserSettings s) => formatValue(goalValue(s));
}
