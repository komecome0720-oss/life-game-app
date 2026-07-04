import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/prediction_accuracy/model/prediction_accuracy_config.dart';

void main() {
  group('errorFor', () {
    test('30分予測60分実績で+100%', () {
      final e = PredictionAccuracyConfig.errorFor(
        predictedMinutes: 30,
        actualMinutes: 60,
      );
      expect(e, closeTo(1.0, 1e-9));
    });

    test('20分予測15分実績で-25%', () {
      final e = PredictionAccuracyConfig.errorFor(
        predictedMinutes: 20,
        actualMinutes: 15,
      );
      expect(e, closeTo(-0.25, 1e-9));
    });
  });

  group('rollingAverage', () {
    test('空リストは null', () {
      expect(PredictionAccuracyConfig.rollingAverage([]), isNull);
    });

    test('符号付き平均で+100%と-100%は相殺されて0%になる', () {
      final avg = PredictionAccuracyConfig.rollingAverage([1.0, -1.0]);
      expect(avg, closeTo(0.0, 1e-9));
    });

    test('直近30件だけを使う（31件目以降は無視）', () {
      final errors = [...List<double>.filled(29, 0.0), 1.0];
      // 新しい順: 先頭が最新。31件目として大きく外れた値を追加しても無視される。
      final withExtra = [...errors, 100.0];
      final avg = PredictionAccuracyConfig.rollingAverage(withExtra);
      expect(avg, closeTo(1.0 / 30, 1e-9));
    });
  });

  group('maxGoodTierIndexFor', () {
    test('10個未満はフツーの人(index 0)が上限', () {
      expect(PredictionAccuracyConfig.maxGoodTierIndexFor(0), 0);
      expect(PredictionAccuracyConfig.maxGoodTierIndexFor(9), 0);
    });

    test('30個以上は神(index 5)まで解禁', () {
      expect(PredictionAccuracyConfig.maxGoodTierIndexFor(30), 5);
      expect(PredictionAccuracyConfig.maxGoodTierIndexFor(100), 5);
    });

    test('段階的な刻み', () {
      expect(PredictionAccuracyConfig.maxGoodTierIndexFor(14), 1);
      expect(PredictionAccuracyConfig.maxGoodTierIndexFor(19), 2);
      expect(PredictionAccuracyConfig.maxGoodTierIndexFor(24), 3);
      expect(PredictionAccuracyConfig.maxGoodTierIndexFor(29), 4);
    });
  });

  group('titleFor', () {
    test('-50%以下は常にビビリ（データ数に関係なく）', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: -0.6,
          cumulativeCount: 0,
        ),
        'ビビリ',
      );
    });

    test('100%以上は時間の迷子', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: 1.2,
          cumulativeCount: 100,
        ),
        '時間の迷子',
      );
    });

    test('データ十分（30個以上）で0%付近は時間を司りし神', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: 0.0,
          cumulativeCount: 30,
        ),
        '時間を司りし神',
      );
    });

    test('データ不足（10個未満）だと0%でもフツーの人止まり', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: 0.0,
          cumulativeCount: 5,
        ),
        'フツーの人',
      );
    });

    test('50%はフツーの人、49%は時間読み見習い', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: 0.50,
          cumulativeCount: 100,
        ),
        'フツーの人',
      );
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: 0.49,
          cumulativeCount: 100,
        ),
        '時間読み見習い',
      );
    });

    test('悪い側の称号はアンロック対象外（データ0でも100%は時間の迷子のまま）', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: 1.5,
          cumulativeCount: 0,
        ),
        '時間の迷子',
      );
    });
  });
}
