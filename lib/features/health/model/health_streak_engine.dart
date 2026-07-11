import 'package:task_manager/features/economy/model/budget_split.dart';
import 'package:task_manager/features/health/model/health_streak_state.dart';

/// リビルド（再計算）ロジックのバージョン。ロジックを変更したら上げる。
/// state.rebuildVersion がこれ未満なら次回前進時にリビルドを走らせる。
const int kStreakRebuildVersion = 1;

/// ストリーク機能導入エポック（'yyyy-MM-dd'）。
/// ver2.2.0＝コミット823ba1d（2026-07-09）の前日で、ユーザー報告の96点日を含む。
/// リビルドはこの日以降のみを対象とし、それより前の健康ログ（ストリーク導入前から存在）には
/// フリーズ消費・リセット・称号付与を遡及適用しない（仕様「これから先に適用」の原則）。
const String kStreakEpochDateKey = '2026-07-08';

/// [advanceOneDay] への1日分の入力。
class DayInput {
  const DayInput({
    required this.dateKey,
    required this.ratio,
    required this.isPerfect,
    required this.monthKey,
  });

  /// 対象日（'yyyy-MM-dd'）。
  final String dateKey;

  /// その日の達成率（0.0〜1.0）。ログが無ければ0。
  final double ratio;

  /// その日が満点（ratio>=1.0）だったか。
  final bool isPerfect;

  /// 対象日が属する月（'yyyy-MM'）。フリーズの月替り再付与の判定に使う。
  final String monthKey;
}

/// [advanceOneDay] の結果。
class DayResult {
  const DayResult({required this.state, required this.outcome});

  final HealthStreakState state;

  /// 'qualified' | 'perfect' | 'frozen' | 'broken'
  final String outcome;
}

/// 純粋関数：ストリークを1日分だけ前進させる。
///
/// 1) 月替りならフリーズを [kFreezeMonthlyGrant] 個に再付与（繰り越しなし）。
/// 2) 達成率が [kHealthStreakRatio] 以上なら達成：streakCount++、称号を付与。
///    満点（[DayInput.isPerfect]）ならフリーズ+1（上限 [kFreezeMax]）。
/// 3) 未達ならフリーズを1個消費して連続日数を維持（'frozen'）。
///    フリーズが0個なら streakCount を0にリセット（'broken'）。
DayResult advanceOneDay(HealthStreakState state, DayInput input) {
  var st = state;
  if (st.freezeMonthKey != input.monthKey) {
    st = st.copyWith(
      freezesRemaining: kFreezeMonthlyGrant,
      freezeMonthKey: input.monthKey,
    );
  }

  final qualified = input.ratio >= kHealthStreakRatio;
  if (qualified) {
    final count = st.streakCount + 1;
    var freezes = st.freezesRemaining;
    if (input.isPerfect) {
      freezes = freezes + 1 > kFreezeMax ? kFreezeMax : freezes + 1;
    }
    final titles = _mergeTitle(st.achievedTitles, count);
    final next = st.copyWith(
      streakCount: count,
      lastQualifiedDateKey: input.dateKey,
      freezesRemaining: freezes,
      achievedTitles: titles,
    );
    return DayResult(
      state: next,
      outcome: input.isPerfect ? 'perfect' : 'qualified',
    );
  }

  if (st.freezesRemaining > 0) {
    final next = st.copyWith(freezesRemaining: st.freezesRemaining - 1);
    return DayResult(state: next, outcome: 'frozen');
  }

  final next = st.copyWith(streakCount: 0);
  return DayResult(state: next, outcome: 'broken');
}

List<String> _mergeTitle(List<String> titles, int count) {
  final title = streakTitleForCount(count);
  if (title == null || titles.contains(title)) return titles;
  return [...titles, title];
}

/// [rebuildStreak] の結果。state と、日付→outcome のマップ。
class RebuildResult {
  const RebuildResult({required this.state, required this.outcomes});

  final HealthStreakState state;

  /// dateKey → 'qualified' | 'perfect' | 'frozen' | 'broken'
  final Map<String, String> outcomes;
}

/// 純粋関数：ログ履歴から streakCount / freezesRemaining / dayOutcome を一括再計算する。
///
/// [base] の achievedTitles は保持したまま、streakCount=0・freezesRemaining=0・
/// freezeMonthKey=null（→初日の月替り判定で再付与される）・lastQualifiedDateKey=null
/// を初期状態に、[days]（dateKey 昇順であること）を [advanceOneDay] で順に適用する。
/// lastProcessedDateKey / rebuildVersion の付与は呼び出し側の責務。
RebuildResult rebuildStreak(HealthStreakState base, List<DayInput> days) {
  var state = HealthStreakState(
    streakCount: 0,
    lastQualifiedDateKey: null,
    lastProcessedDateKey: base.lastProcessedDateKey,
    freezesRemaining: 0,
    freezeMonthKey: null,
    achievedTitles: base.achievedTitles,
    rebuildVersion: base.rebuildVersion,
  );
  final outcomes = <String, String>{};
  for (final day in days) {
    final result = advanceOneDay(state, day);
    state = result.state;
    outcomes[day.dateKey] = result.outcome;
  }
  return RebuildResult(state: state, outcomes: outcomes);
}
