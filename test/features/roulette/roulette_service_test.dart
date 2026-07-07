import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/features/roulette/data/roulette_repository.dart';
import 'package:task_manager/features/roulette/data/roulette_service.dart';
import 'package:task_manager/features/roulette/model/reward_config.dart';
import 'package:task_manager/features/roulette/model/roulette_outcome.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';

class _MockRouletteRepository extends Mock implements RouletteRepository {}

/// [RewardConfig.categoryForRoll] の乱数を固定するためのfake。
/// nextDouble() は常に[rollValue]、nextInt()は常に0を返す（ご褒美リストの先頭を選ぶ）。
class _FixedRandom implements math.Random {
  _FixedRandom(this.rollValue);

  final double rollValue;

  @override
  double nextDouble() => rollValue;

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

void main() {
  setUpAll(() {
    registerFallbackValue(RouletteCategory.miss);
  });

  late _MockRouletteRepository mockRepo;
  const settings = UserSettings();

  setUp(() {
    mockRepo = _MockRouletteRepository();
  });

  test('ハズレ着地時はissueTicketが呼ばれない', () async {
    // 大+中+小の確率合計未満にはならない、十分大きいrollでハズレに着地させる。
    final service = RouletteService(mockRepo, random: _FixedRandom(0.999999));

    final outcome = await service.spin(completionId: 'c1', settings: settings);

    expect(outcome.kind, RouletteOutcomeKind.nearMiss);
    verifyNever(
      () => mockRepo.issueTicket(
        completionId: any(named: 'completionId'),
        tier: any(named: 'tier'),
        rewardName: any(named: 'rewardName'),
      ),
    );
  });

  test('当たり(中)着地時、issueTicketの完了を待たずにspin()が完了する', () async {
    final completer = Completer<void>();
    when(
      () => mockRepo.issueTicket(
        completionId: any(named: 'completionId'),
        tier: any(named: 'tier'),
        rewardName: any(named: 'rewardName'),
      ),
    ).thenAnswer((_) => completer.future);

    // 中当たりの確率帯に入るroll値（jackpot確率0.0268を超え、chu確率まで）。
    final service = RouletteService(mockRepo, random: _FixedRandom(0.1));

    final outcome = await service
        .spin(completionId: 'c1', settings: settings)
        .timeout(const Duration(seconds: 2));

    expect(outcome.kind, RouletteOutcomeKind.win);
    expect(outcome.tier, RouletteCategory.chu);
    verify(
      () => mockRepo.issueTicket(
        completionId: 'c1',
        tier: RouletteCategory.chu,
        rewardName: any(named: 'rewardName'),
      ),
    ).called(1);

    completer.complete();
  });

  test('issueTicketが例外を投げてもspin()は例外を伝播せずwinを返す', () async {
    when(
      () => mockRepo.issueTicket(
        completionId: any(named: 'completionId'),
        tier: any(named: 'tier'),
        rewardName: any(named: 'rewardName'),
      ),
    ).thenAnswer((_) => Future<void>.error(Exception('issue failed')));

    final service = RouletteService(mockRepo, random: _FixedRandom(0.1));

    final outcome = await service.spin(completionId: 'c1', settings: settings);

    expect(outcome.kind, RouletteOutcomeKind.win);
    expect(outcome.tier, RouletteCategory.chu);
  });
}
