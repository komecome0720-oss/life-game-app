import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/economy/model/reward_calculator.dart';

void main() {
  group('rewardYenFor', () {
    test('時間単価と分数から報酬額を四捨五入で算出する', () {
      expect(rewardYenFor(hourlyRate: 3000, minutes: 60), 3000);
      expect(rewardYenFor(hourlyRate: 3000, minutes: 30), 1500);
      expect(rewardYenFor(hourlyRate: 1000, minutes: 1), 17); // 1000/60=16.67→17
    });

    test('hourlyRateまたはminutesが0以下なら0を返す', () {
      expect(rewardYenFor(hourlyRate: 0, minutes: 60), 0);
      expect(rewardYenFor(hourlyRate: 3000, minutes: 0), 0);
      expect(rewardYenFor(hourlyRate: -100, minutes: 60), 0);
    });
  });
}
