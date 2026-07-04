/// 時間予測精度ゲームの「調整可能パラメータ」と「純粋ロジック」を集約する
/// （[RewardConfig] と同じ方針: マジックナンバーをロジック内に直書きしない）。
///
/// 誤差の定義: 1タスクにつき `(実績分 - 予測分) / 予測分`（符号付き）。
/// 全体指標はこの誤差の直近30件ローリング平均（符号付き、相殺あり）。
class PredictionAccuracyConfig {
  PredictionAccuracyConfig._();

  /// ローリング平均の対象件数。
  static const int rollingWindowSize = 30;

  /// 「ビビリ」の閾値。平均誤差がこの値以下（早く終わらせすぎ）だと
  /// アンロック状況に関係なく「ビビリ」になる。
  static const double biBiriThreshold = -0.5;

  /// 良い側の称号（フツーの人〜時間を司りし神）を良い順に並べたもの。
  /// index が大きいほど良い称号。悪い側（フツーの人より下限%が高い側）は
  /// アンロック対象外のため、この配列には含めない。
  static const List<TierBand> goodTierBands = [
    TierBand(minPercent: 50, title: 'フツーの人'),
    TierBand(minPercent: 40, title: '時間読み見習い'),
    TierBand(minPercent: 30, title: 'ニアピン職人'),
    TierBand(minPercent: 20, title: 'ほぼ的中請負人'),
    TierBand(minPercent: 10, title: '予測の達人'),
    TierBand(minPercent: null, title: '時間を司りし神'), // -50%超〜10%未満
  ];

  /// 悪い側の称号（フツーの人より悪い）を悪い順に並べたもの。
  /// アンロック対象外（データ数に関係なく常に出る）。
  static const List<TierBand> badTierBands = [
    TierBand(minPercent: 100, title: '時間の迷子'),
    TierBand(minPercent: 90, title: 'お花畑タイムキーパー'),
    TierBand(minPercent: 80, title: 'ふわっと予報士'),
    TierBand(minPercent: 70, title: 'どんぶり勘定さん'),
    TierBand(minPercent: 60, title: '夢見がち系'),
  ];

  /// 累計データ数 → 獲得可能な最高称号（[goodTierBands] のインデックス）。
  /// 昇順（データ数の少ない条件を先に判定できるよう小さい順）で並べる。
  static const List<UnlockStep> unlockSteps = [
    UnlockStep(minCumulativeCount: 0, maxGoodTierIndex: 0), // フツーの人
    UnlockStep(minCumulativeCount: 10, maxGoodTierIndex: 1), // 時間読み見習い
    UnlockStep(minCumulativeCount: 15, maxGoodTierIndex: 2), // ニアピン職人
    UnlockStep(minCumulativeCount: 20, maxGoodTierIndex: 3), // ほぼ的中請負人
    UnlockStep(minCumulativeCount: 25, maxGoodTierIndex: 4), // 予測の達人
    UnlockStep(minCumulativeCount: 30, maxGoodTierIndex: 5), // 時間を司りし神
  ];

  /// 1タスクの誤差（符号付き、割合。+1.0 = +100%）。
  /// [predictedMinutes] は正の値であること（呼び出し側でガード済み前提）。
  static double errorFor({
    required int predictedMinutes,
    required int actualMinutes,
  }) {
    return (actualMinutes - predictedMinutes) / predictedMinutes;
  }

  /// 直近 [rollingWindowSize] 件の誤差（新しい順に並んでいる前提）の
  /// 符号付き平均。空リストなら null。
  static double? rollingAverage(List<double> errorsNewestFirst) {
    final window = errorsNewestFirst.take(rollingWindowSize).toList();
    if (window.isEmpty) return null;
    return window.reduce((a, b) => a + b) / window.length;
  }

  /// 累計データ数から、獲得できる最高称号（[goodTierBands] のインデックス）を返す。
  static int maxGoodTierIndexFor(int cumulativeCount) {
    var cap = unlockSteps.first.maxGoodTierIndex;
    for (final step in unlockSteps) {
      if (cumulativeCount >= step.minCumulativeCount) {
        cap = step.maxGoodTierIndex;
      }
    }
    return cap;
  }

  /// 平均誤差（割合。+1.0 = +100%）と累計データ数から称号を算出する。
  static String titleFor({
    required double averageError,
    required int cumulativeCount,
  }) {
    if (averageError <= biBiriThreshold) return 'ビビリ';

    final percent = averageError * 100;
    for (final band in badTierBands) {
      if (percent >= band.minPercent!) return band.title;
    }

    var rawIndex = goodTierBands.length - 1; // デフォルト: 神
    for (var i = 0; i < goodTierBands.length; i++) {
      final minPercent = goodTierBands[i].minPercent;
      if (minPercent != null && percent >= minPercent) {
        rawIndex = i;
        break;
      }
    }

    final capIndex = maxGoodTierIndexFor(cumulativeCount);
    final finalIndex = rawIndex < capIndex ? rawIndex : capIndex;
    return goodTierBands[finalIndex].title;
  }
}

/// 称号バンドの1区切り。[minPercent] は「この%以上」で適用される下限
/// （null は良い側の最上位＝下限なしを意味する）。
class TierBand {
  const TierBand({required this.minPercent, required this.title});

  final double? minPercent;
  final String title;
}

/// 累計データ数によるアンロック段。
class UnlockStep {
  const UnlockStep({
    required this.minCumulativeCount,
    required this.maxGoodTierIndex,
  });

  final int minCumulativeCount;
  final int maxGoodTierIndex;
}
