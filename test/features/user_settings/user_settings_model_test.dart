import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/roulette/model/reward_config.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';

void main() {
  group('UserSettings weeklyChuCount', () {
    test('default で中当たり数を持つ', () {
      const settings = UserSettings();
      expect(settings.weeklyChuCount, RewardConfig.defaultWeeklyChuCount);
    });

    test('copyWith で中当たり数を更新できる', () {
      const settings = UserSettings();
      final updated = settings.copyWith(weeklyChuCount: 12.5);
      expect(updated.weeklyChuCount, 12.5);
      expect(settings.weeklyChuCount, RewardConfig.defaultWeeklyChuCount);
    });

    test('toFirestore に weeklyChuCount を含める', () {
      const settings = UserSettings(weeklyChuCount: 9.5);
      final data = settings.toFirestore();
      expect(data['weeklyChuCount'], 9.5);
    });
  });

  group('UserSettings weeklyShoCount', () {
    test('default で小当たり数を持つ', () {
      const settings = UserSettings();
      expect(settings.weeklyShoCount, RewardConfig.defaultWeeklyShoCount);
    });

    test('copyWith で小当たり数を更新できる', () {
      const settings = UserSettings();
      final updated = settings.copyWith(weeklyShoCount: 20.5);
      expect(updated.weeklyShoCount, 20.5);
      expect(settings.weeklyShoCount, RewardConfig.defaultWeeklyShoCount);
    });

    test('toFirestore に weeklyShoCount を含める', () {
      const settings = UserSettings(weeklyShoCount: 25.5);
      final data = settings.toFirestore();
      expect(data['weeklyShoCount'], 25.5);
    });
  });

  group('UserSettings onboardingCompleted', () {
    test('default で false を持つ', () {
      const settings = UserSettings();
      expect(settings.onboardingCompleted, isFalse);
    });

    test('copyWith で true に更新できる', () {
      const settings = UserSettings();
      final updated = settings.copyWith(onboardingCompleted: true);
      expect(updated.onboardingCompleted, isTrue);
      expect(settings.onboardingCompleted, isFalse);
    });

    test('toFirestore には onboardingCompleted を含めない', () {
      const settings = UserSettings(onboardingCompleted: true);
      final data = settings.toFirestore();
      expect(data.containsKey('onboardingCompleted'), isFalse);
    });

    test('fromFirestore: キー無しなら false', () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('users').doc('u1');
      await ref.set({'displayName': 'たろう'});
      final doc = await ref.get();
      final settings = UserSettings.fromFirestore(doc);
      expect(settings.onboardingCompleted, isFalse);
    });

    test('fromFirestore: true が保存されていれば true', () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('users').doc('u1');
      await ref.set({'onboardingCompleted': true});
      final doc = await ref.get();
      final settings = UserSettings.fromFirestore(doc);
      expect(settings.onboardingCompleted, isTrue);
    });
  });

  group('UserSettings meditationEnabled', () {
    test('default で true を持つ', () {
      const settings = UserSettings();
      expect(settings.meditationEnabled, isTrue);
    });

    test('copyWith で false に更新できる', () {
      const settings = UserSettings();
      final updated = settings.copyWith(meditationEnabled: false);
      expect(updated.meditationEnabled, isFalse);
      expect(settings.meditationEnabled, isTrue);
    });

    test('toFirestore に meditationEnabled を含める（round-trip）', () {
      const settings = UserSettings(meditationEnabled: false);
      final data = settings.toFirestore();
      expect(data['meditationEnabled'], isFalse);
    });

    test('fromFirestore: キー無しなら既定 true', () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('users').doc('u1');
      await ref.set({'displayName': 'たろう'});
      final doc = await ref.get();
      final settings = UserSettings.fromFirestore(doc);
      expect(settings.meditationEnabled, isTrue);
    });

    test('fromFirestore: false が保存されていれば false', () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('users').doc('u1');
      await ref.set({'meditationEnabled': false});
      final doc = await ref.get();
      final settings = UserSettings.fromFirestore(doc);
      expect(settings.meditationEnabled, isFalse);
    });
  });

  group('UserSettings predictionChipMinutes', () {
    test('default で [15,30,45,60,90,120,180] を持つ', () {
      const settings = UserSettings();
      expect(
        settings.predictionChipMinutes,
        UserSettings.defaultPredictionChipMinutes,
      );
    });

    test('copyWith で更新できる', () {
      const settings = UserSettings();
      final updated = settings.copyWith(predictionChipMinutes: [10, 20]);
      expect(updated.predictionChipMinutes, [10, 20]);
      expect(
        settings.predictionChipMinutes,
        UserSettings.defaultPredictionChipMinutes,
      );
    });

    test('toFirestore / fromFirestore の round-trip', () async {
      const settings = UserSettings(predictionChipMinutes: [10, 25, 50]);
      final data = settings.toFirestore();
      expect(data['predictionChipMinutes'], [10, 25, 50]);

      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('users').doc('u1');
      await ref.set({'predictionChipMinutes': [10, 25, 50]});
      final doc = await ref.get();
      final restored = UserSettings.fromFirestore(doc);
      expect(restored.predictionChipMinutes, [10, 25, 50]);
    });

    test('fromFirestore: キー無しならデフォルトプリセット', () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('users').doc('u1');
      await ref.set({'displayName': 'たろう'});
      final doc = await ref.get();
      final settings = UserSettings.fromFirestore(doc);
      expect(
        settings.predictionChipMinutes,
        UserSettings.defaultPredictionChipMinutes,
      );
    });

    test('fromFirestore: 数値以外の要素は除外される', () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('users').doc('u1');
      await ref.set({'predictionChipMinutes': [15, 'x', 30]});
      final doc = await ref.get();
      final settings = UserSettings.fromFirestore(doc);
      expect(settings.predictionChipMinutes, [15, 30]);
    });

    test('fromFirestore: 空リストならデフォルトプリセット', () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('users').doc('u1');
      await ref.set({'predictionChipMinutes': []});
      final doc = await ref.get();
      final settings = UserSettings.fromFirestore(doc);
      expect(
        settings.predictionChipMinutes,
        UserSettings.defaultPredictionChipMinutes,
      );
    });

    test('fromFirestore: 全要素が非数値ならデフォルトプリセット', () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('users').doc('u1');
      await ref.set({'predictionChipMinutes': ['x', 'y']});
      final doc = await ref.get();
      final settings = UserSettings.fromFirestore(doc);
      expect(
        settings.predictionChipMinutes,
        UserSettings.defaultPredictionChipMinutes,
      );
    });
  });

  group('UserSettings taskHourlyRate / healthDailyCapYen / maxActiveHealthScore', () {
    test('taskHourlyRate は hourlyRate の70%', () {
      const settings = UserSettings(
        monthlyBudget: 30000,
        monthlyQuestDays: 20,
        dailyQuestMinutes: 60,
      );
      expect(settings.hourlyRate, 1500.0);
      expect(settings.taskHourlyRate, 1050.0);
    });

    test('healthDailyCapYen は monthlyBudget×30%÷30日', () {
      const settings = UserSettings(monthlyBudget: 30000);
      expect(settings.healthDailyCapYen, 300);
    });

    test('maxActiveHealthScore は瞑想ON=100 / OFF=80', () {
      const on = UserSettings(meditationEnabled: true);
      const off = UserSettings(meditationEnabled: false);
      expect(on.maxActiveHealthScore, 100);
      expect(off.maxActiveHealthScore, 80);
    });
  });
}
