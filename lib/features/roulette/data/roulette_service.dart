import 'dart:math' as math;

import 'package:task_manager/features/roulette/data/roulette_repository.dart';
import 'package:task_manager/features/roulette/model/reward_config.dart';
import 'package:task_manager/features/roulette/model/roulette_outcome.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';

/// タスク完了後のルーレット抽選を統括する。
///
/// 乱数を使うためトランザクションの外で1回だけ抽選し、当たり（中/大）なら
/// [RouletteRepository.issueTicket] を決定的IDで冪等に発行する。小は即時許可（バンクしない）。
class RouletteService {
  RouletteService(this._repo, {math.Random? random})
      : _random = random ?? math.Random();

  final RouletteRepository _repo;
  final math.Random _random;

  /// [completionId]（通常はタスクID）ごとに1回抽選する。チケット発行は冪等。
  Future<RouletteOutcome> spin({
    required String completionId,
    required UserSettings settings,
  }) async {
    final invalid = RewardConfig.validateRouletteInput(
      weeklyTaskCount: settings.weeklyTaskCount,
      weeklyJackpotCount: settings.weeklyJackpotCount,
    );
    if (invalid != null) {
      return const RouletteOutcome.invalidConfig();
    }

    final probs = RewardConfig.probabilitiesFor(
      weeklyTaskCount: settings.weeklyTaskCount,
      weeklyJackpotCount: settings.weeklyJackpotCount,
    );
    final drawn = RewardConfig.categoryForRoll(_random.nextDouble(), probs);

    if (drawn == RouletteCategory.miss) {
      return RouletteOutcome.nearMiss(probabilities: probs);
    }

    final tier = RewardConfig.effectiveTier(
      drawn,
      hasJackpotRewards: settings.jackpotRewards.isNotEmpty,
      hasChuRewards: settings.chuRewards.isNotEmpty,
      hasShoRewards: settings.shoRewards.isNotEmpty,
    );
    if (tier == null) {
      // 当選したがご褒美リストが空（フォールバック先も空）→ 発行せず設定を促す。
      return RouletteOutcome.needsSetup(
        probabilities: probs,
        landedCategory: drawn,
      );
    }

    final rewards = settings.rewardsFor(tier);
    final rewardName = rewards[_random.nextInt(rewards.length)];

    // 中/大はチケットを在庫に発行。小は即時許可なのでバンクしない。
    if (tier.banksTicket) {
      await _repo.issueTicket(
        completionId: completionId,
        tier: tier,
        rewardName: rewardName,
      );
    }

    return RouletteOutcome.win(
      probabilities: probs,
      landedCategory: drawn,
      tier: tier,
      rewardName: rewardName,
      banked: tier.banksTicket,
    );
  }
}
