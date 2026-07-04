import 'package:task_manager/features/prediction_accuracy/model/prediction_accuracy_config.dart';

/// ホーム画面のステータスパネルに表示する時間予測精度の集計結果。
class PredictionAccuracyStats {
  const PredictionAccuracyStats({
    required this.averageError,
    required this.cumulativeCount,
  });

  /// 直近30件の符号付き平均誤差（+1.0 = +100%）。対象データが1件も無ければ null。
  final double? averageError;

  /// 対象データ（予測・実績とも記録済みの完了タスク）の累計数。
  final int cumulativeCount;

  /// 表示用の称号。対象データが無ければ null。
  String? get title {
    final error = averageError;
    if (error == null) return null;
    return PredictionAccuracyConfig.titleFor(
      averageError: error,
      cumulativeCount: cumulativeCount,
    );
  }

  /// 表示用の整数%（符号付き）。対象データが無ければ null。
  int? get percentRounded {
    final error = averageError;
    if (error == null) return null;
    return (error * 100).round();
  }
}
