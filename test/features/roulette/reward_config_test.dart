import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/roulette/model/reward_config.dart';

void main() {
  group('配分比率', () {
    test('大以外の3区分の比率は合計1.0', () {
      expect(
        RewardConfig.hazureRatio +
            RewardConfig.chuRatio +
            RewardConfig.shoRatio,
        closeTo(1.0, 1e-12),
      );
    });
  });

  group('probabilitiesFor', () {
    test('P(大)=J/W、P(中)=C/W、P(小)=S/W、残りが全てハズレで合計1.0', () {
      final p = RewardConfig.probabilitiesFor(
        weeklyTaskCount: 56,
        weeklyJackpotCount: 1.5,
        weeklyChuCount: 16.35,
        weeklyShoCount: 30,
      );
      expect(p.jackpot, closeTo(1.5 / 56, 1e-12));
      expect(p.chu, closeTo(16.35 / 56, 1e-12));
      expect(p.sho, closeTo(30 / 56, 1e-12));
      expect(
        p.miss,
        closeTo(1 - p.jackpot - p.chu - p.sho, 1e-12),
      );
      expect(p.total, closeTo(1.0, 1e-12));
      expect(p.jackpotClamped, isFalse);
      expect(p.chuClamped, isFalse);
      expect(p.shoClamped, isFalse);
    });

    test('JACKPOT_CAP を超える J/W はクランプされ clamped=true', () {
      final p = RewardConfig.probabilitiesFor(
        weeklyTaskCount: 10,
        weeklyJackpotCount: 5, // raw=0.5 > 0.10
        weeklyChuCount: 1,
        weeklyShoCount: 1,
      );
      expect(p.jackpot, RewardConfig.jackpotCap);
      expect(p.jackpotClamped, isTrue);
      expect(p.total, closeTo(1.0, 1e-12));
    });

    test('中当たりが残り確率を超えるとクランプされる（小もハズレも0）', () {
      final p = RewardConfig.probabilitiesFor(
        weeklyTaskCount: 10,
        weeklyJackpotCount: 1,
        weeklyChuCount: 20,
        weeklyShoCount: 0,
      );
      expect(p.jackpot, 0.10);
      expect(p.chu, 0.90);
      expect(p.sho, 0.0);
      expect(p.miss, 0.0);
      expect(p.chuClamped, isTrue);
      expect(p.shoClamped, isFalse);
      expect(p.total, closeTo(1.0, 1e-12));
    });

    test('小当たりが残り確率を超えるとクランプされ shoClamped=true', () {
      final p = RewardConfig.probabilitiesFor(
        weeklyTaskCount: 10,
        weeklyJackpotCount: 1,
        weeklyChuCount: 1,
        weeklyShoCount: 20, // raw=2.0、残り確率(1-0.1-0.1=0.8)を超過
      );
      expect(p.jackpot, 0.10);
      expect(p.chu, 0.10);
      expect(p.sho, closeTo(0.80, 1e-12));
      expect(p.miss, closeTo(0.0, 1e-12));
      expect(p.shoClamped, isTrue);
      expect(p.total, closeTo(1.0, 1e-12));
    });

    test('chuClamped と shoClamped が同時発生（中が残りを食い尽くしmaxSho=0）', () {
      final p = RewardConfig.probabilitiesFor(
        weeklyTaskCount: 10,
        weeklyJackpotCount: 1, // P(大)=0.10
        weeklyChuCount: 20, // raw=2.0 > maxChu(0.90) → クランプでchu=0.90
        weeklyShoCount: 5, // maxSho = 1-0.10-0.90 = 0 → クランプでsho=0
      );
      expect(p.jackpot, 0.10);
      expect(p.chu, closeTo(0.90, 1e-12));
      expect(p.sho, closeTo(0.0, 1e-12));
      expect(p.miss, closeTo(0.0, 1e-12));
      expect(p.chuClamped, isTrue);
      expect(p.shoClamped, isTrue);
      expect(p.total, closeTo(1.0, 1e-12));
    });

    test('J=0 は P(大)=0、ハズレ/中/小のみ', () {
      final p = RewardConfig.probabilitiesFor(
        weeklyTaskCount: 30,
        weeklyJackpotCount: 0,
        weeklyChuCount: 6,
        weeklyShoCount: 10,
      );
      expect(p.jackpot, 0.0);
      expect(p.total, closeTo(1.0, 1e-12));
    });

    test('S=0 のとき miss が残り確率全部', () {
      final p = RewardConfig.probabilitiesFor(
        weeklyTaskCount: 56,
        weeklyJackpotCount: 1.5,
        weeklyChuCount: 16.35,
        weeklyShoCount: 0,
      );
      expect(p.sho, 0.0);
      expect(p.shoClamped, isFalse);
      expect(p.miss, closeTo(1 - p.jackpot - p.chu, 1e-12));
      expect(p.total, closeTo(1.0, 1e-12));
    });

    test('W<=0 は ArgumentError', () {
      expect(
        () => RewardConfig.probabilitiesFor(
          weeklyTaskCount: 0,
          weeklyJackpotCount: 1,
          weeklyChuCount: 0,
          weeklyShoCount: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => RewardConfig.probabilitiesFor(
          weeklyTaskCount: -3,
          weeklyJackpotCount: 1,
          weeklyChuCount: 0,
          weeklyShoCount: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('validateRouletteInput', () {
    test('正常入力は null', () {
      expect(
        RewardConfig.validateRouletteInput(
          weeklyTaskCount: 56,
          weeklyJackpotCount: 1.5,
          weeklyChuCount: 16.35,
          weeklyShoCount: 30,
        ),
        isNull,
      );
    });

    test('W<=0 はエラー文言', () {
      expect(
        RewardConfig.validateRouletteInput(
          weeklyTaskCount: 0,
          weeklyJackpotCount: 1,
          weeklyChuCount: 0,
          weeklyShoCount: 0,
        ),
        isNotNull,
      );
    });

    test('J<0 はエラー文言', () {
      expect(
        RewardConfig.validateRouletteInput(
          weeklyTaskCount: 56,
          weeklyJackpotCount: -1,
          weeklyChuCount: 0,
          weeklyShoCount: 0,
        ),
        isNotNull,
      );
    });

    test('C<0 はエラー文言', () {
      expect(
        RewardConfig.validateRouletteInput(
          weeklyTaskCount: 56,
          weeklyJackpotCount: 1,
          weeklyChuCount: -1,
          weeklyShoCount: 0,
        ),
        isNotNull,
      );
    });

    test('S<0 はエラー文言', () {
      expect(
        RewardConfig.validateRouletteInput(
          weeklyTaskCount: 56,
          weeklyJackpotCount: 1,
          weeklyChuCount: 0,
          weeklyShoCount: -1,
        ),
        isNotNull,
      );
    });
  });

  group('categoryForRoll', () {
    final p = RewardConfig.probabilitiesFor(
      weeklyTaskCount: 56,
      weeklyJackpotCount: 1.5,
      weeklyChuCount: 16.35,
      weeklyShoCount: 30,
    );

    test('累積境界で大→中→小→ハズレに割り当てる', () {
      expect(RewardConfig.categoryForRoll(0.0, p), RouletteCategory.jackpot);
      // 大の直後 = 中の先頭
      expect(
        RewardConfig.categoryForRoll(p.jackpot + 1e-9, p),
        RouletteCategory.chu,
      );
      // 中の直後 = 小の先頭
      expect(
        RewardConfig.categoryForRoll(p.jackpot + p.chu + 1e-9, p),
        RouletteCategory.sho,
      );
      // 小の直後 = ハズレ
      expect(
        RewardConfig.categoryForRoll(p.jackpot + p.chu + p.sho + 1e-9, p),
        RouletteCategory.miss,
      );
      // 末尾
      expect(RewardConfig.categoryForRoll(0.999999, p), RouletteCategory.miss);
    });

    test('多数サンプルで分布が設定確率に収束する（仕様§5）', () {
      final rng = math.Random(20260613);
      const n = 200000;
      final counts = <RouletteCategory, int>{
        RouletteCategory.jackpot: 0,
        RouletteCategory.chu: 0,
        RouletteCategory.sho: 0,
        RouletteCategory.miss: 0,
      };
      for (var i = 0; i < n; i++) {
        final c = RewardConfig.categoryForRoll(rng.nextDouble(), p);
        counts[c] = counts[c]! + 1;
      }
      // 許容誤差は ±0.01（10万件超なら十分収束する）。
      expect(counts[RouletteCategory.jackpot]! / n, closeTo(p.jackpot, 0.01));
      expect(counts[RouletteCategory.chu]! / n, closeTo(p.chu, 0.01));
      expect(counts[RouletteCategory.sho]! / n, closeTo(p.sho, 0.01));
      expect(counts[RouletteCategory.miss]! / n, closeTo(p.miss, 0.01));
    });
  });

  group('effectiveTier（空リストのフォールバック 大→中→小）', () {
    test('在庫があればそのまま', () {
      expect(
        RewardConfig.effectiveTier(
          RouletteCategory.jackpot,
          hasJackpotRewards: true,
          hasChuRewards: true,
          hasShoRewards: true,
        ),
        RouletteCategory.jackpot,
      );
    });

    test('大が空なら中へ、中も空なら小へ', () {
      expect(
        RewardConfig.effectiveTier(
          RouletteCategory.jackpot,
          hasJackpotRewards: false,
          hasChuRewards: true,
          hasShoRewards: true,
        ),
        RouletteCategory.chu,
      );
      expect(
        RewardConfig.effectiveTier(
          RouletteCategory.jackpot,
          hasJackpotRewards: false,
          hasChuRewards: false,
          hasShoRewards: true,
        ),
        RouletteCategory.sho,
      );
    });

    test('小まで全部空なら null（チケット発行せず設定を促す）', () {
      expect(
        RewardConfig.effectiveTier(
          RouletteCategory.jackpot,
          hasJackpotRewards: false,
          hasChuRewards: false,
          hasShoRewards: false,
        ),
        isNull,
      );
      expect(
        RewardConfig.effectiveTier(
          RouletteCategory.sho,
          hasJackpotRewards: true,
          hasChuRewards: true,
          hasShoRewards: false,
        ),
        isNull,
      );
    });

    test('ハズレは常に null（下位区分へ流さない）', () {
      expect(
        RewardConfig.effectiveTier(
          RouletteCategory.miss,
          hasJackpotRewards: true,
          hasChuRewards: true,
          hasShoRewards: true,
        ),
        isNull,
      );
    });
  });

  group('banksTicket / isWin', () {
    test('小は当選だがバンクしない、ハズレは非当選', () {
      expect(RouletteCategory.jackpot.banksTicket, isTrue);
      expect(RouletteCategory.chu.banksTicket, isTrue);
      expect(RouletteCategory.sho.banksTicket, isFalse);
      expect(RouletteCategory.sho.isWin, isTrue);
      expect(RouletteCategory.miss.isWin, isFalse);
      expect(RouletteCategory.miss.banksTicket, isFalse);
    });
  });

  group('boardCells', () {
    test('9マスで大1/中2/小3/ハズレ3、角度合計1.0', () {
      final p = RewardConfig.probabilitiesFor(
        weeklyTaskCount: 56,
        weeklyJackpotCount: 1.5,
        weeklyChuCount: 16.35,
        weeklyShoCount: 30,
      );
      final cells = RewardConfig.boardCells(p);
      expect(cells.length, RewardConfig.boardCellCount);
      expect(cells.length, 9);

      int countOf(RouletteCategory c) =>
          cells.where((cell) => cell.category == c).length;
      expect(countOf(RouletteCategory.jackpot), 1);
      expect(countOf(RouletteCategory.chu), 2);
      expect(countOf(RouletteCategory.sho), 3);
      expect(countOf(RouletteCategory.miss), 3);

      final total = cells.fold<double>(0, (s, c) => s + c.sweepFraction);
      expect(total, closeTo(1.0, 1e-12));

      // 中の各マス = P(中)/2、小の各マス = P(小)/3、ハズレの各マス = P(ハズレ)/3
      for (final cell in cells.where(
        (c) => c.category == RouletteCategory.chu,
      )) {
        expect(cell.sweepFraction, closeTo(p.chu / 2, 1e-12));
      }
      for (final cell in cells.where(
        (c) => c.category == RouletteCategory.sho,
      )) {
        expect(cell.sweepFraction, closeTo(p.sho / 3, 1e-12));
      }
      for (final cell in cells.where(
        (c) => c.category == RouletteCategory.miss,
      )) {
        expect(cell.sweepFraction, closeTo(p.miss / 3, 1e-12));
      }
    });

    test('同じ区分のマスが隣り合わない（円環で判定）', () {
      final p = RewardConfig.probabilitiesFor(
        weeklyTaskCount: 56,
        weeklyJackpotCount: 1.5,
        weeklyChuCount: 16.35,
        weeklyShoCount: 30,
      );
      final cells = RewardConfig.boardCells(p);
      for (var i = 0; i < cells.length; i++) {
        final next = cells[(i + 1) % cells.length];
        expect(
          cells[i].category,
          isNot(next.category),
          reason: 'マス$i と ${(i + 1) % cells.length} が同区分',
        );
      }
    });
  });

  group('legacyWeeklyChuCountFor', () {
    test('旧ロジックの中当たり率を維持する値を逆算できる', () {
      final count = RewardConfig.legacyWeeklyChuCountFor(
        weeklyTaskCount: 56,
        weeklyJackpotCount: 1.5,
      );
      expect(count, closeTo(16.35, 1e-12));
    });

    test('不正なWは初期値へフォールバックする', () {
      expect(
        RewardConfig.legacyWeeklyChuCountFor(
          weeklyTaskCount: 0,
          weeklyJackpotCount: 1.5,
        ),
        RewardConfig.defaultWeeklyChuCount,
      );
    });
  });

  group('legacyWeeklyShoCountFor', () {
    test('旧ロジックの小当たり率を維持する値を逆算できる（小数第2位に丸め）', () {
      final count = RewardConfig.legacyWeeklyShoCountFor(
        weeklyTaskCount: 56,
        weeklyJackpotCount: 1.5,
        weeklyChuCount: 16.35,
      );
      expect(count, 29.97);
    });

    test('不正なWは初期値へフォールバックする', () {
      expect(
        RewardConfig.legacyWeeklyShoCountFor(
          weeklyTaskCount: 0,
          weeklyJackpotCount: 1.5,
          weeklyChuCount: 16.35,
        ),
        RewardConfig.defaultWeeklyShoCount,
      );
    });
  });

  group('requiredCumulativeForLevel C(L)', () {
    test('C(1)=0、低レベルは仕様の目安表どおり', () {
      expect(RewardConfig.requiredCumulativeForLevel(1), 0);
      expect(RewardConfig.requiredCumulativeForLevel(2), 3);
      expect(RewardConfig.requiredCumulativeForLevel(3), 10);
      expect(RewardConfig.requiredCumulativeForLevel(4), 21);
      expect(RewardConfig.requiredCumulativeForLevel(5), 36);
    });

    test('L<=1 は 0 にクランプ', () {
      expect(RewardConfig.requiredCumulativeForLevel(0), 0);
      expect(RewardConfig.requiredCumulativeForLevel(-5), 0);
    });

    test('広範囲で狭義単調増加（C(L+1) > C(L)）', () {
      for (var l = 1; l < 500; l++) {
        expect(
          RewardConfig.requiredCumulativeForLevel(l + 1),
          greaterThan(RewardConfig.requiredCumulativeForLevel(l)),
          reason: 'C($l) と C(${l + 1}) が単調増加でない',
        );
      }
    });
  });

  group('levelForCumulative / progressFor', () {
    test('累計から現在レベルを算出（C(L)<=count を満たす最大L）', () {
      expect(RewardConfig.levelForCumulative(0), 1);
      expect(RewardConfig.levelForCumulative(2), 1);
      expect(RewardConfig.levelForCumulative(3), 2);
      expect(RewardConfig.levelForCumulative(9), 2);
      expect(RewardConfig.levelForCumulative(10), 3);
      expect(RewardConfig.levelForCumulative(35), 4);
      expect(RewardConfig.levelForCumulative(36), 5);
    });

    test('負の累計は0として扱う', () {
      expect(RewardConfig.levelForCumulative(-10), 1);
    });

    test('進捗 fraction と remaining が正しい', () {
      // count=0: Lv1、次=C(2)=3、進捗0/3
      final p0 = RewardConfig.progressFor(0);
      expect(p0.level, 1);
      expect(p0.currentLevelFloor, 0);
      expect(p0.nextLevelRequirement, 3);
      expect(p0.tasksForNextLevel, 3);
      expect(p0.tasksIntoLevel, 0);
      expect(p0.remainingToNext, 3);
      expect(p0.fraction, closeTo(0.0, 1e-12));

      // count=5: Lv2（floor=3,next=10,span=7,into=2）
      final p5 = RewardConfig.progressFor(5);
      expect(p5.level, 2);
      expect(p5.currentLevelFloor, 3);
      expect(p5.nextLevelRequirement, 10);
      expect(p5.tasksIntoLevel, 2);
      expect(p5.tasksForNextLevel, 7);
      expect(p5.remainingToNext, 5);
      expect(p5.fraction, closeTo(2 / 7, 1e-12));
    });

    test('累計がレベル到達ちょうどなら fraction=0', () {
      final p = RewardConfig.progressFor(3); // Lv2 のちょうど境界
      expect(p.level, 2);
      expect(p.fraction, closeTo(0.0, 1e-12));
    });
  });

  group('titleForLevel 称号', () {
    test('レベル帯ごとの称号', () {
      expect(RewardConfig.titleForLevel(1), '駆け出し');
      expect(RewardConfig.titleForLevel(4), '駆け出し');
      expect(RewardConfig.titleForLevel(5), '常連');
      expect(RewardConfig.titleForLevel(9), '常連');
      expect(RewardConfig.titleForLevel(10), '達人');
      expect(RewardConfig.titleForLevel(19), '達人');
      expect(RewardConfig.titleForLevel(20), '名人');
      expect(RewardConfig.titleForLevel(100), '名人');
    });
  });
}
