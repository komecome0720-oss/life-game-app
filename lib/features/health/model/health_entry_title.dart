import 'package:task_manager/features/health/model/health_category.dart';
import 'package:task_manager/features/health/model/health_log.dart';

const String healthEntryFallbackTitle = '健康スコア';

/// 冒険の記録に載せる健康エントリのタイトルを組み立てる。
///
/// [baseline] から [current] にかけて値が変わったカテゴリのみを
/// 「運動 +15 分・瞑想 +10 分」のように増減表記で列挙する。
/// 変更が無い、または baseline が使えない場合は目標変更等による
/// 再計算差分とみなし [healthEntryFallbackTitle] を返す。
String buildHealthEntryTitle(HealthLog? baseline, HealthLog current) {
  if (baseline == null || baseline.dateKey != current.dateKey) {
    return healthEntryFallbackTitle;
  }

  final parts = <String>[];
  for (final category in HealthCategory.values) {
    final before = category.currentValue(baseline);
    final after = category.currentValue(current);
    final diff = _roundToOneDecimal(after - before);
    if (diff == 0) continue;
    final sign = diff > 0 ? '+' : '-';
    parts.add('${category.label} $sign${category.formatValue(diff.abs())}');
  }

  if (parts.isEmpty) return healthEntryFallbackTitle;
  return parts.join('・');
}

double _roundToOneDecimal(double value) => (value * 10).roundToDouble() / 10;
