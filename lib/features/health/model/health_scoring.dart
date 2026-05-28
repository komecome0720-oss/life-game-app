/// 健康ログの採点・報酬計算ユーティリティ
class HealthScoring {
  HealthScoring._();

  /// 0〜10 段階への変換（表示用、小数点切り捨て）。goal <= 0 の場合は 0。
  /// 例: current=100, goal=300 → 100/300*10 = 3.33 → 3
  static int level(num current, num goal) {
    if (goal <= 0) return 0;
    final v = (current / goal * 10).floor();
    if (v < 0) return 0;
    if (v > 10) return 10;
    return v;
  }

  /// 重み付きの点数 (0 〜 weight*10)。比率から直接算出するため、
  /// `level × weight` ではなく丸め誤差なく目標に対する達成度を反映する。
  /// 例: current=100, goal=300, weight=3 → 100/300*30 = 10
  static int score(num current, num goal, int weight) {
    if (goal <= 0 || weight <= 0) return 0;
    final max = weight * 10;
    final v = (current / goal * max).round();
    if (v < 0) return 0;
    if (v > max) return max;
    return v;
  }

  /// 合計点(0〜100) と時間単価から、獲得金額を算出。
  /// 100点 = 1日分(24時間)の1/8 = 3時間分の時間単価。
  static int earningsForPoints(int points, double hourlyRate) {
    if (hourlyRate <= 0 || points <= 0) return 0;
    return (hourlyRate * 3 * points / 100).round();
  }
}
