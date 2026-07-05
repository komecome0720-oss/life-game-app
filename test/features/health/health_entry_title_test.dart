import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/health/model/health_entry_title.dart';
import 'package:task_manager/features/health/model/health_log.dart';

void main() {
  group('buildHealthEntryTitle', () {
    const dateKey = '2026-07-05';

    test('単一カテゴリの増加を「カテゴリ +量」で表す', () {
      const baseline = HealthLog(dateKey: dateKey);
      const current = HealthLog(dateKey: dateKey, exerciseMinutes: 30);

      expect(buildHealthEntryTitle(baseline, current), '運動 +30 分');
    });

    test('複数カテゴリの変更を「・」で連結する', () {
      const baseline = HealthLog(
        dateKey: dateKey,
        exerciseMinutes: 30,
        meditationMinutes: 0,
      );
      const current = HealthLog(
        dateKey: dateKey,
        exerciseMinutes: 45,
        meditationMinutes: 10,
      );

      expect(buildHealthEntryTitle(baseline, current), '運動 +15 分・瞑想 +10 分');
    });

    test('値が減った場合はマイナス表記になる', () {
      const baseline = HealthLog(dateKey: dateKey, exerciseMinutes: 30);
      const current = HealthLog(dateKey: dateKey, exerciseMinutes: 15);

      expect(buildHealthEntryTitle(baseline, current), '運動 -15 分');
    });

    test('睡眠は時間・分の複合表記になる', () {
      const baseline = HealthLog(dateKey: dateKey);
      const current = HealthLog(dateKey: dateKey, sleepMinutes: 270);

      expect(buildHealthEntryTitle(baseline, current), '睡眠 +4時間30分');
    });

    test('値が変わっていなければ健康スコアにフォールバックする', () {
      const baseline = HealthLog(dateKey: dateKey, exerciseMinutes: 30);
      const current = HealthLog(dateKey: dateKey, exerciseMinutes: 30);

      expect(buildHealthEntryTitle(baseline, current), healthEntryFallbackTitle);
    });

    test('baselineがnullなら健康スコアにフォールバックする', () {
      const current = HealthLog(dateKey: dateKey, exerciseMinutes: 30);

      expect(buildHealthEntryTitle(null, current), healthEntryFallbackTitle);
    });

    test('baselineの日付が異なれば健康スコアにフォールバックする', () {
      const baseline = HealthLog(dateKey: '2026-07-04', exerciseMinutes: 0);
      const current = HealthLog(dateKey: dateKey, exerciseMinutes: 30);

      expect(buildHealthEntryTitle(baseline, current), healthEntryFallbackTitle);
    });
  });
}
