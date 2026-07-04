import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/prediction_accuracy/data/prediction_accuracy_repository.dart';
import 'package:task_manager/features/prediction_accuracy/model/prediction_accuracy_stats.dart';

final predictionAccuracyRepositoryProvider =
    Provider<PredictionAccuracyRepository>(
  (_) => PredictionAccuracyRepository(),
);

/// ホーム画面のステータスパネルで watch する時間予測精度の集計。
final predictionAccuracyStatsProvider =
    StreamProvider.autoDispose<PredictionAccuracyStats>((ref) {
  return ref.watch(predictionAccuracyRepositoryProvider).watchStats();
});
