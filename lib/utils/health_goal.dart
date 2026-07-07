import 'package:flutter/material.dart';

/// 健康管理の合計点（100点満点）の目標値
const healthGoals = [30, 60, 80];

/// 合計点に応じた色（線ちょうどで昇格）
/// 0=灰 / 1〜29=青 / 30〜59=緑 / 60〜79=黄(アンバー) / 80〜=赤
Color healthTotalColor(int score, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  if (score >= 80) return dark ? Colors.red.shade300 : Colors.red.shade600;
  if (score >= 60) return dark ? Colors.amber.shade400 : Colors.amber.shade700;
  if (score >= 30) return dark ? Colors.green.shade300 : Colors.green.shade600;
  if (score >= 1) return dark ? Colors.blue.shade300 : Colors.blue.shade600;
  return dark ? Colors.grey.shade600 : Colors.grey.shade500;
}
