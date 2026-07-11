import 'package:task_manager/features/prediction_accuracy/model/prediction_accuracy_config.dart';

/// ホーム画面のステータスパネルに表示する時間予測精度の集計結果。
class PredictionAccuracyStats {
  const PredictionAccuracyStats({
    required this.averageError,
    required this.cumulativeCount,
    this.windowCount = 0,
  });

  /// 直近30件の符号付き平均誤差（+1.0 = +100%）。対象データが1件も無ければ null。
  final double? averageError;

  /// 対象データ（宣言済み予測・実績とも記録済みの完了タスク）の累計数。
  final int cumulativeCount;

  /// ローリング平均に実際に使われた件数（`min(cumulativeCount, 30)`）。
  final int windowCount;

  /// 表示用の称号。対象データが無い、または悪い側・ビビリ系で件数不足なら null（計測中）。
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

  /// 件数不足で称号が出せない（計測中）場合の残件数。称号が出ている／対象データが無い場合は null。
  int? get measuringRemainder {
    final error = averageError;
    if (error == null) return null;
    if (title != null) return null;
    final remaining =
        PredictionAccuracyConfig.minCountForNegativeTitles - cumulativeCount;
    return remaining > 0 ? remaining : null;
  }

  /// 次の良い側称号アンロックまでの残件数・称号名。最上位まで解禁済みなら null。
  NextUnlockInfo? get nextUnlock {
    for (final step in PredictionAccuracyConfig.unlockSteps) {
      if (cumulativeCount < step.minCumulativeCount) {
        return NextUnlockInfo(
          remaining: step.minCumulativeCount - cumulativeCount,
          title: PredictionAccuracyConfig
              .goodTierBands[step.maxGoodTierIndex].title,
        );
      }
    }
    return null;
  }
}

/// 次の称号アンロックまでの残件数と、その称号名。
class NextUnlockInfo {
  const NextUnlockInfo({required this.remaining, required this.title});

  final int remaining;
  final String title;
}
