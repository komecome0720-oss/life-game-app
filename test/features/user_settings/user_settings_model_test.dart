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
}
