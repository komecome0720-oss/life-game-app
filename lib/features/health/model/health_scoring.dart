import 'package:task_manager/features/economy/model/budget_split.dart';

/// 健康ログの採点・報酬計算ユーティリティ
class HealthScoring {
  HealthScoring._();

  /// 0〜10 段階への変換（表示用、小数点切り捨て）。
  /// [baseline] がある場合は baseline が0、goal が10になる。
  static int level(num current, num goal, {num baseline = 0}) {
    final denominator = goal - baseline;
    if (denominator <= 0) return 0;
    final adjusted = (current - baseline).clamp(0, denominator);
    final v = (adjusted / denominator * 10).floor();
    if (v < 0) return 0;
    if (v > 10) return 10;
    return v;
  }

  /// 重み付きの点数 (0 〜 weight*10)。比率から直接算出するため、
  /// `level × weight` ではなく丸め誤差なく目標に対する達成度を反映する。
  static int score(num current, num goal, int weight, {num baseline = 0}) {
    final denominator = goal - baseline;
    if (denominator <= 0 || weight <= 0) return 0;
    final max = weight * 10;
    final adjusted = (current - baseline).clamp(0, denominator);
    final v = (adjusted / denominator * max).round();
    if (v < 0) return 0;
    if (v > max) return max;
    return v;
  }

  /// 有効項目の満点。瞑想ON=100 / OFF=80。
  static int maxActiveScore({required bool meditationEnabled}) =>
      meditationEnabled ? 100 : 80;

  /// 達成率 0.0〜1.0。
  static double achievementRatio(int totalScore, int maxActiveScore) {
    if (maxActiveScore <= 0) return 0;
    return (totalScore / maxActiveScore).clamp(0.0, 1.0);
  }

  /// 線形・40%ゲート。p<0.40 は 0（没収）。p>=0.40 は round(cap × p)。
  static int earningsForRatio({
    required double ratio,
    required int dailyCapYen,
  }) {
    if (dailyCapYen <= 0) return 0;
    if (ratio < kHealthGateRatio) return 0;
    return (dailyCapYen * ratio).round();
  }
}
