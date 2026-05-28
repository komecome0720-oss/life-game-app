import 'package:flutter/material.dart';
import 'package:task_manager/features/health/model/health_log.dart';
import 'package:task_manager/features/health/model/health_scoring.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';

/// 健康カテゴリ。スライダー仕様・目標取得・表示・採点重みを集約する。
enum HealthCategory { meal, exercise, sleep, meditation }

extension HealthCategoryX on HealthCategory {
  String get label => switch (this) {
        HealthCategory.meal => '食事',
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

  // ── スライダー仕様 ───────────────────────────────────────────
  /// 単位つきで表示する場面あり（g / 分）
  double get sliderMin => switch (this) {
        HealthCategory.meal => 0,
        HealthCategory.exercise => 0,
        HealthCategory.sleep => 240, // 4h
        HealthCategory.meditation => 0,
      };

  double get sliderMax => switch (this) {
        HealthCategory.meal => 600,
        HealthCategory.exercise => 30,
        HealthCategory.sleep => 480, // 8h
        HealthCategory.meditation => 15,
      };

  double get sliderStep => switch (this) {
        HealthCategory.meal => 50,
        HealthCategory.exercise => 5,
        HealthCategory.sleep => 15,
        HealthCategory.meditation => 1,
      };

  int get sliderDivisions =>
      ((sliderMax - sliderMin) / sliderStep).round();

  // ── 目標・現在値の取得 ───────────────────────────────────────
  int goalValue(UserSettings s) => switch (this) {
        HealthCategory.meal => s.mealGoalGrams,
        HealthCategory.exercise => s.exerciseGoalMinutes,
        HealthCategory.sleep => s.sleepGoalHours * 60 + s.sleepGoalMinutesExtra,
        HealthCategory.meditation => s.meditationGoalMinutes,
      };

  int currentValue(HealthLog log) => switch (this) {
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
  int level(HealthLog log, UserSettings s) =>
      HealthScoring.level(currentValue(log), goalValue(s));

  // ── 表示整形 ─────────────────────────────────────────────────
  String formatValue(int v) {
    switch (this) {
      case HealthCategory.meal:
        return '$v g';
      case HealthCategory.exercise:
      case HealthCategory.meditation:
        return '$v 分';
      case HealthCategory.sleep:
        final h = v ~/ 60;
        final m = v % 60;
        if (m == 0) return '$h 時間';
        return '$h時間$m分';
    }
  }

  String formatGoal(UserSettings s) => formatValue(goalValue(s));
}
