import 'package:task_manager/features/economy/model/budget_split.dart';
import 'package:task_manager/features/health/model/health_streak_state.dart';

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
