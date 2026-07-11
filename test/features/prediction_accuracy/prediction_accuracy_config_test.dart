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

    test('+300%相当の誤差は+1.0でクランプされる', () {
      final e = PredictionAccuracyConfig.errorFor(
        predictedMinutes: 30,
        actualMinutes: 150,
      );
      expect(e, closeTo(1.0, 1e-9));
    });

    test('-300%相当の誤差は-1.0でクランプされる', () {
      final e = PredictionAccuracyConfig.errorFor(
        predictedMinutes: 30,
        actualMinutes: -60,
      );
      expect(e, closeTo(-1.0, 1e-9));
    });

    test('5分予測10分実績は分母が15分にfloorされて+0.333…', () {
      final e = PredictionAccuracyConfig.errorFor(
        predictedMinutes: 5,
        actualMinutes: 10,
      );
      expect(e, closeTo(5 / 15, 1e-9));
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

  group('titleFor 境界', () {
    test('-9.99%はアンロック済みなら神帯', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: -0.0999,
          cumulativeCount: 30,
        ),
        '時間を司りし神',
      );
    });

    test('-10.0%はちょいビビリ', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: -0.10,
          cumulativeCount: 10,
        ),
        'ちょいビビリ',
      );
    });

    test('-20.0%はビビリ見習い', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: -0.20,
          cumulativeCount: 10,
        ),
        'ビビリ見習い',
      );
    });

    test('-95%は時間を買い占めし者', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: -0.95,
          cumulativeCount: 10,
        ),
        '時間を買い占めし者',
      );
    });

    test('+10.0%は予測の達人（アンロック済み）', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: 0.10,
          cumulativeCount: 30,
        ),
        '予測の達人',
      );
    });

    test('+70%はどんぶり勘定さん', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: 0.70,
          cumulativeCount: 10,
        ),
        'どんぶり勘定さん',
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
  });

  group('5件ゲート', () {
    test('cumulativeCount=4 で percent=-30 は null（計測中）', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: -0.30,
          cumulativeCount: 4,
        ),
        isNull,
      );
    });

    test('cumulativeCount=4 で percent=+70 は null（計測中）', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: 0.70,
          cumulativeCount: 4,
        ),
        isNull,
      );
    });

    test('cumulativeCount=4 でも良い側 percent=+5 は現行どおり称号あり', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: 0.05,
          cumulativeCount: 4,
        ),
        isNotNull,
      );
    });

    test('cumulativeCount=5 なら percent=-30 でビビリが出る', () {
      expect(
        PredictionAccuracyConfig.titleFor(
          averageError: -0.30,
          cumulativeCount: 5,
        ),
        'ビビリ',
      );
    });
  });
}
