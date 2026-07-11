import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/health/model/health_log.dart';
import 'package:task_manager/features/health/model/health_scoring.dart';
import 'package:task_manager/features/health/model/health_streak_engine.dart';
import 'package:task_manager/features/health/model/health_streak_state.dart';

DayInput _day(
  String dateKey, {
  required double ratio,
  bool isPerfect = false,
  String monthKey = '2026-07',
}) {
  return DayInput(
    dateKey: dateKey,
    ratio: ratio,
    isPerfect: isPerfect,
    monthKey: monthKey,
  );
}

void main() {
  group('advanceOneDay 基本', () {
    test('連続達成でstreakCountが増える', () {
      var state = const HealthStreakState();
      final r1 = advanceOneDay(state, _day('2026-07-01', ratio: 0.85));
      expect(r1.state.streakCount, 1);
      expect(r1.outcome, 'qualified');
      state = r1.state;

      final r2 = advanceOneDay(state, _day('2026-07-02', ratio: 0.90));
      expect(r2.state.streakCount, 2);
      expect(r2.outcome, 'qualified');
    });

    test('達成率ちょうど0.80は達成扱い（境界含む）', () {
      final r = advanceOneDay(
        const HealthStreakState(),
        _day('2026-07-01', ratio: 0.80),
      );
      expect(r.outcome, 'qualified');
      expect(r.state.streakCount, 1);
    });

    test('達成率0.79未満は未達扱い', () {
      final r = advanceOneDay(
        const HealthStreakState(freezesRemaining: 0, freezeMonthKey: '2026-07'),
        _day('2026-07-01', ratio: 0.79),
      );
      expect(r.outcome, 'broken');
    });
  });

  group('100%達成でフリーズ+1', () {
    test('満点日はfreezesRemainingが1増える', () {
      final r = advanceOneDay(
        const HealthStreakState(freezesRemaining: 1, freezeMonthKey: '2026-07'),
        _day('2026-07-01', ratio: 1.0, isPerfect: true),
      );
      expect(r.outcome, 'perfect');
      expect(r.state.freezesRemaining, 2);
      expect(r.state.streakCount, 1);
    });

    test('freeze上限5でクランプされる', () {
      final r = advanceOneDay(
        const HealthStreakState(freezesRemaining: 5, freezeMonthKey: '2026-07'),
        _day('2026-07-01', ratio: 1.0, isPerfect: true),
      );
      expect(r.state.freezesRemaining, 5);
    });
  });

  group('未達時のフリーズ消費とリセット', () {
    test('p<0.80でfreeze>0ならフリーズを1個消費してstreakは維持', () {
      final r = advanceOneDay(
        const HealthStreakState(
          streakCount: 5,
          freezesRemaining: 2,
          freezeMonthKey: '2026-07',
        ),
        _day('2026-07-01', ratio: 0.10),
      );
      expect(r.outcome, 'frozen');
      expect(r.state.streakCount, 5); // 維持
      expect(r.state.freezesRemaining, 1);
    });

    test('freeze0で未達ならstreakCountが0にリセットされる', () {
      final r = advanceOneDay(
        const HealthStreakState(
          streakCount: 5,
          freezesRemaining: 0,
          freezeMonthKey: '2026-07',
        ),
        _day('2026-07-01', ratio: 0.0),
      );
      expect(r.outcome, 'broken');
      expect(r.state.streakCount, 0);
      expect(r.state.freezesRemaining, 0);
    });

    test('未入力日（ratio=0）も未達として扱われる', () {
      final r = advanceOneDay(
        const HealthStreakState(freezesRemaining: 0, freezeMonthKey: '2026-07'),
        _day('2026-07-01', ratio: 0.0),
      );
      expect(r.outcome, 'broken');
    });
  });

  group('月替りでのフリーズ再付与（繰り越しなし）', () {
    test('月が変わるとfreezesRemainingが2にリセットされる（前月の残数を無視）', () {
      final r = advanceOneDay(
        const HealthStreakState(freezesRemaining: 4, freezeMonthKey: '2026-06'),
        _day('2026-07-01', ratio: 0.0, monthKey: '2026-07'),
      );
      // 月替りで2に再付与された後、未達で1消費される。
      expect(r.state.freezeMonthKey, '2026-07');
      expect(r.state.freezesRemaining, 1);
      expect(r.outcome, 'frozen');
    });

    test('同月内ではfreezeMonthKeyが変わらず再付与されない', () {
      final r = advanceOneDay(
        const HealthStreakState(freezesRemaining: 1, freezeMonthKey: '2026-07'),
        _day('2026-07-15', ratio: 0.85, monthKey: '2026-07'),
      );
      expect(r.state.freezeMonthKey, '2026-07');
      expect(r.state.freezesRemaining, 1); // 達成なので消費されない・再付与もされない
    });
  });

  group('節目で称号が付与される', () {
    test('3日目に到達すると称号が追加される', () {
      final state = const HealthStreakState(streakCount: 2, freezeMonthKey: '2026-07');
      final r = advanceOneDay(state, _day('2026-07-03', ratio: 0.85));
      expect(r.state.streakCount, 3);
      expect(r.state.achievedTitles, contains('習慣の芽'));
    });

    test('節目でない日数では称号が追加されない', () {
      final state = const HealthStreakState(
        streakCount: 3,
        freezeMonthKey: '2026-07',
        achievedTitles: ['習慣の芽'],
      );
      final r = advanceOneDay(state, _day('2026-07-04', ratio: 0.85));
      expect(r.state.streakCount, 4);
      expect(r.state.achievedTitles, ['習慣の芽']);
    });

    test('複数節目を跨いでも重複追加されない', () {
      final state = const HealthStreakState(
        streakCount: 6,
        freezeMonthKey: '2026-07',
        achievedTitles: ['習慣の芽'],
      );
      final r = advanceOneDay(state, _day('2026-07-07', ratio: 0.85));
      expect(r.state.streakCount, 7);
      expect(r.state.achievedTitles, ['習慣の芽', '一週間の勇者']);
    });
  });

  group('lastQualifiedDateKey', () {
    test('達成日にlastQualifiedDateKeyが更新される', () {
      final r = advanceOneDay(
        const HealthStreakState(),
        _day('2026-07-05', ratio: 0.85),
      );
      expect(r.state.lastQualifiedDateKey, '2026-07-05');
    });

    test('未達日ではlastQualifiedDateKeyは変わらない', () {
      final r = advanceOneDay(
        const HealthStreakState(
          lastQualifiedDateKey: '2026-07-04',
          freezesRemaining: 1,
        ),
        _day('2026-07-05', ratio: 0.10),
      );
      expect(r.state.lastQualifiedDateKey, '2026-07-04');
    });
  });

  group('rebuildStreak', () {
    test('高スコア日(0.96)→未達→未達 でstreakCountが1のまま維持される（ユーザー報告シナリオの再現）', () {
      final result = rebuildStreak(const HealthStreakState(), [
        _day('2026-07-08', ratio: 0.96),
        _day('2026-07-09', ratio: 0.0),
        _day('2026-07-10', ratio: 0.0),
      ]);
      expect(result.state.streakCount, 1);
      expect(result.outcomes['2026-07-08'], 'qualified');
      expect(result.outcomes['2026-07-09'], 'frozen');
      expect(result.outcomes['2026-07-10'], 'frozen');
      expect(result.state.freezesRemaining, 0); // 月初2個付与→2日消費で0
    });

    test('月替りを跨ぐとフリーズが2個に再付与される', () {
      final result = rebuildStreak(const HealthStreakState(), [
        _day('2026-06-29', ratio: 0.0, monthKey: '2026-06'),
        _day('2026-06-30', ratio: 0.0, monthKey: '2026-06'),
        _day('2026-07-01', ratio: 0.0, monthKey: '2026-07'),
      ]);
      // 6月分は2個付与→2日で使い切り0。7月に入り2個へ再付与→1日消費で1。
      expect(result.state.freezeMonthKey, '2026-07');
      expect(result.state.freezesRemaining, 1);
    });

    test('baseのachievedTitlesが保持されたまま新称号がマージされる', () {
      final base = const HealthStreakState(achievedTitles: ['習慣の芽']);
      final days = List.generate(
        7,
        (i) => _day('2026-07-0${i + 1}', ratio: 0.85),
      );
      final result = rebuildStreak(base, days);
      expect(result.state.streakCount, 7);
      expect(result.state.achievedTitles, ['習慣の芽', '一週間の勇者']);
    });

    test('フリーズ0で未達日を挟むとstreakCountがリセットされる', () {
      final result = rebuildStreak(const HealthStreakState(), [
        _day('2026-07-01', ratio: 0.85), // qualified, streak=1
        _day('2026-07-02', ratio: 0.10), // frozen, freeze 2->1
        _day('2026-07-03', ratio: 0.10), // frozen, freeze 1->0
        _day('2026-07-04', ratio: 0.10), // freeze0 → broken
      ]);
      expect(result.outcomes['2026-07-04'], 'broken');
      expect(result.state.streakCount, 0);
      expect(result.state.freezesRemaining, 0);
    });
  });

  group('HealthScoring.ratioOf', () {
    test('瞑想ONスナップショット(max100)でtotalScore96→0.96', () {
      const log = HealthLog(
        dateKey: '2026-07-08',
        totalScore: 96,
        achievedPercent: 0.0,
        meditationEnabledSnapshot: true,
      );
      expect(HealthScoring.ratioOf(log), closeTo(0.96, 0.0001));
    });

    test('瞑想OFFスナップショット(max80)でtotalScore64→0.8（成立境界）', () {
      const log = HealthLog(
        dateKey: '2026-07-08',
        totalScore: 64,
        achievedPercent: 0.0,
        meditationEnabledSnapshot: false,
      );
      expect(HealthScoring.ratioOf(log), closeTo(0.8, 0.0001));
    });
  });
}
