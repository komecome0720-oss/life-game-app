import 'package:flutter/material.dart';
import 'package:task_manager/features/economy/model/budget_split.dart';

/// 達成率(0.0〜1.0)に応じた色（線ちょうどで昇格）。§5-B。
/// 0%=灰 / 1〜39%=青(没収ゾーン=まだ0円) / 40〜59%=緑 / 60〜79%=黄(アンバー) / 80%以上=赤(ストリーク成立)
Color healthTotalColor(double percent, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  if (percent >= kHealthStreakRatio) {
    return dark ? Colors.red.shade300 : Colors.red.shade600;
  }
  if (percent >= 0.60) {
    return dark ? Colors.amber.shade400 : Colors.amber.shade700;
  }
  if (percent >= kHealthGateRatio) {
    return dark ? Colors.green.shade300 : Colors.green.shade600;
  }
  if (percent > 0) return dark ? Colors.blue.shade300 : Colors.blue.shade600;
  return dark ? Colors.grey.shade600 : Colors.grey.shade500;
}
