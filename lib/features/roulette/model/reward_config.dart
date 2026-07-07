import 'dart:math' as math;

/// ルーレット報酬＆レベルシステムの「調整可能パラメータ」と「純粋ロジック」を
/// 1か所に集約するユーティリティ（仕様§0.6: マジックナンバーをロジック内に直書きしない）。
///
/// ここに含まれるのは Firebase 非依存の純関数のみ。データ永続化・抽選の乱数生成・UI は
/// 上位レイヤ（repository / viewmodel / view）が担う。乱数は [categoryForRoll] のように
/// roll 値を注入する形にして、ロジック自体を決定的・テスト可能に保つ。
class RewardConfig {
  RewardConfig._();

  // ---------------------------------------------------------------------------
  // ルーレット配分比率。新ロジックでは大・中・小はすべて明示入力（週あたり回数から逆算）で、
  // 残り確率は全てハズレになる。この比率定数は weeklyChuCount / weeklyShoCount 導入前の
  // 保存データを逆算するための legacy 専用値（現行ロジックでは使用しない）。
  // ---------------------------------------------------------------------------
  static const double hazureRatio = 0.15;
  static const double chuRatio = 0.30;
  static const double shoRatio = 0.55;

  /// 大当たり確率の上限。J/W が大きすぎると大当たりが日常化し「特別な許可」という
  /// 設計意図が壊れるため、超過分はこの値でクランプする。
  static const double jackpotCap = 0.10;

  // ---------------------------------------------------------------------------
  // 盤面構成（固定: 大×1 / 中×2 / 小×3 / ハズレ×3 = 9マス）。
  // マスの角度（面積）＝当選確率に比例（等分割ではない）。
  // ---------------------------------------------------------------------------
  static const int chuCells = 2;
  static const int shoCells = 3;
  static const int missCells = 3;
  static const int boardCellCount = 1 + chuCells + shoCells + missCells; // = 9

  // ---------------------------------------------------------------------------
  // レベル曲線 C(L) = floor(A * (L - 1)^P)  （L>=1, C(1)=0）。ポケモン式の逓増カーブ。
  // ---------------------------------------------------------------------------
  static const double levelCoefficientA = 3;
  static const double levelExponentP = 1.8;

  /// 称号バンド（仮称・後で変更可）。`minLevel` 昇順で並べること。
  static const List<TitleBand> titleBands = [
    TitleBand(minLevel: 1, title: '駆け出し'),
    TitleBand(minLevel: 5, title: '常連'),
    TitleBand(minLevel: 10, title: '達人'),
    TitleBand(minLevel: 20, title: '名人'),
  ];

  // ---------------------------------------------------------------------------
  // ご褒美登録のデフォルト（初回シード用）。各区分3枠まで開けておく（窮屈さ回避）。
  // ---------------------------------------------------------------------------
  static const int rewardSlotsPerTier = 3;
  static const List<String> defaultJackpotRewards = ['映画を観る'];
  static const List<String> defaultChuRewards = ['近所の公園を散歩'];
  static const List<String> defaultShoRewards = ['好きな飲み物で休憩'];

  /// ルーレット設定の初期値（仕様2.3の例に準拠。後から設定画面で変更可）。
  static const double defaultWeeklyTaskCount = 56;
  static const double defaultWeeklyJackpotCount = 1.5;
  static const double defaultWeeklyChuCount = 16.35;
  static const double defaultWeeklyShoCount = 30;

  // ===========================================================================
  // 入力バリデーション
  // ===========================================================================

  /// 週単位の入力検証。問題なければ null、あれば日本語エラー文言を返す。
  static String? validateRouletteInput({
    required num weeklyTaskCount,
    required num weeklyJackpotCount,
    required num weeklyChuCount,
    required num weeklyShoCount,
  }) {
    if (weeklyTaskCount <= 0) {
      return '週あたりのタスク予定回数は1以上で入力してください';
    }
    if (weeklyJackpotCount < 0) {
      return '週に欲しい大当たり回数は0以上で入力してください';
    }
    if (weeklyChuCount < 0) {
      return '週に欲しい中当たり回数は0以上で入力してください';
    }
    if (weeklyShoCount < 0) {
      return '週に欲しい小当たり回数は0以上で入力してください';
    }
    return null;
  }

  // ===========================================================================
  // 確率の動的生成（コアロジック）
  // ===========================================================================

  /// 4区分（大／中／小／ハズレ）の確率を算出する。
  ///
  /// ```
  /// P(大)    = clamp(J / W, 0, JACKPOT_CAP)
  /// P(中)    = clamp(C / W, 0, 1 - P(大))
  /// P(小)    = clamp(S / W, 0, 1 - P(大) - P(中))
  /// P(ハズレ) = 1 - P(大) - P(中) - P(小)
  /// ```
  ///
  /// 大 → 中 → 小 の順に確率を確保し、残りは全てハズレになる。
  /// 合計は必ず 1.0 になる。[weeklyTaskCount] <= 0 は不正入力なので [ArgumentError]
  /// （呼び出し側は事前に [validateRouletteInput] でガードすること）。
  static RouletteProbabilities probabilitiesFor({
    required num weeklyTaskCount,
    required num weeklyJackpotCount,
    required num weeklyChuCount,
    required num weeklyShoCount,
  }) {
    if (weeklyTaskCount <= 0) {
      throw ArgumentError.value(
        weeklyTaskCount,
        'weeklyTaskCount',
        '0 より大きい必要があります',
      );
    }
    final rawJackpot = weeklyJackpotCount / weeklyTaskCount;
    final jackpotClamped = rawJackpot > jackpotCap;
    final pJackpot = rawJackpot < 0
        ? 0.0
        : (jackpotClamped ? jackpotCap : rawJackpot.toDouble());
    final rawChu = weeklyChuCount / weeklyTaskCount;
    final maxChu = 1 - pJackpot;
    final chuClamped = rawChu > maxChu;
    final pChu = rawChu < 0 ? 0.0 : (chuClamped ? maxChu : rawChu.toDouble());
    final rawSho = weeklyShoCount / weeklyTaskCount;
    final maxSho = 1 - pJackpot - pChu;
    final shoClamped = rawSho > maxSho;
    final pSho = rawSho < 0 ? 0.0 : (shoClamped ? maxSho : rawSho.toDouble());
    final pMiss = (1 - pJackpot - pChu - pSho).clamp(0.0, 1.0).toDouble();
    return RouletteProbabilities(
      jackpot: pJackpot,
      chu: pChu,
      sho: pSho,
      miss: pMiss,
      jackpotClamped: jackpotClamped,
      chuClamped: chuClamped,
      shoClamped: shoClamped,
    );
  }

  /// `weeklyChuCount` 導入前の保存データから、中当たり設定値を逆算して体験を維持する。
  static double legacyWeeklyChuCountFor({
    required num weeklyTaskCount,
    required num weeklyJackpotCount,
  }) {
    if (weeklyTaskCount <= 0) return defaultWeeklyChuCount;
    final p = probabilitiesFor(
      weeklyTaskCount: weeklyTaskCount,
      weeklyJackpotCount: weeklyJackpotCount,
      weeklyChuCount: 0,
      weeklyShoCount: 0,
    );
    return weeklyTaskCount * ((1 - p.jackpot) * chuRatio);
  }

  /// `weeklyShoCount` 導入前の保存データから、小当たり設定値を逆算して体験を維持する。
  /// 旧ロジックの remaining（= 1 - P(大) - P(中)）を 小:ハズレ = [shoRatio]:[hazureRatio]
  /// で配分していた比率をそのまま使い、体感確率を変えない。
  static double legacyWeeklyShoCountFor({
    required num weeklyTaskCount,
    required num weeklyJackpotCount,
    required num weeklyChuCount,
  }) {
    if (weeklyTaskCount <= 0) return defaultWeeklyShoCount;
    final p = probabilitiesFor(
      weeklyTaskCount: weeklyTaskCount,
      weeklyJackpotCount: weeklyJackpotCount,
      weeklyChuCount: weeklyChuCount,
      weeklyShoCount: 0,
    );
    final remaining = p.miss;
    final raw = weeklyTaskCount * remaining * shoRatio / (shoRatio + hazureRatio);
    return (raw * 100).roundToDouble() / 100;
  }

  /// roll ∈ [0, 1) を 4区分へ割り当てる（乱数を注入してロジックを決定的に保つ）。
  /// 累積順: 大 → 中 → 小 → ハズレ。
  static RouletteCategory categoryForRoll(
    double roll,
    RouletteProbabilities p,
  ) {
    final r = roll.clamp(0.0, 1.0 - 1e-12).toDouble();
    if (r < p.jackpot) return RouletteCategory.jackpot;
    if (r < p.jackpot + p.chu) return RouletteCategory.chu;
    if (r < p.jackpot + p.chu + p.sho) return RouletteCategory.sho;
    return RouletteCategory.miss;
  }

  /// 当選区分のご褒美リストが空のときのフォールバック（大→中→小）。
  /// ハズレはそのまま当選なし（null）。小も在庫が無ければ null（チケット発行せず設定を促す）。
  static RouletteCategory? effectiveTier(
    RouletteCategory drawn, {
    required bool hasJackpotRewards,
    required bool hasChuRewards,
    required bool hasShoRewards,
  }) {
    if (drawn == RouletteCategory.miss) return null;
    const order = [
      RouletteCategory.jackpot,
      RouletteCategory.chu,
      RouletteCategory.sho,
    ];
    final has = <RouletteCategory, bool>{
      RouletteCategory.jackpot: hasJackpotRewards,
      RouletteCategory.chu: hasChuRewards,
      RouletteCategory.sho: hasShoRewards,
    };
    for (var i = order.indexOf(drawn); i < order.length; i++) {
      if (has[order[i]] == true) return order[i];
    }
    return null;
  }

  /// 盤面9マスの構成。各マスの [RouletteCell.sweepFraction]（円全体に対する角度割合）の
  /// 合計は 1.0。中は[chuCells]マス、小は[shoCells]マス、ハズレは[missCells]マスで
  /// 確率を均等に分け合う。演出上、同じ区分が偏って見えないよう交互に散らして配置する。
  static List<RouletteCell> boardCells(RouletteProbabilities p) {
    final chuEach = p.chu / chuCells;
    final shoEach = p.sho / shoCells;
    final missEach = p.miss / missCells;
    return [
      RouletteCell(RouletteCategory.jackpot, p.jackpot),
      RouletteCell(RouletteCategory.sho, shoEach),
      RouletteCell(RouletteCategory.chu, chuEach),
      RouletteCell(RouletteCategory.miss, missEach),
      RouletteCell(RouletteCategory.sho, shoEach),
      RouletteCell(RouletteCategory.miss, missEach),
      RouletteCell(RouletteCategory.chu, chuEach),
      RouletteCell(RouletteCategory.sho, shoEach),
      RouletteCell(RouletteCategory.miss, missEach),
    ];
  }

  // ===========================================================================
  // レベルシステム
  // ===========================================================================

  /// レベル [level] に到達するために必要な累計タスク数 C(L)。C(1)=0、L<=1 は 0。
  /// 純関数・単調増加（reward_config_test で広範囲に保証）。
  static int requiredCumulativeForLevel(int level) {
    if (level <= 1) return 0;
    return (levelCoefficientA * math.pow(level - 1, levelExponentP)).floor();
  }

  /// 累計タスク数から現在レベルを算出する。C(L) <= [cumulativeTasks] を満たす最大の L。
  static int levelForCumulative(int cumulativeTasks) {
    final count = cumulativeTasks < 0 ? 0 : cumulativeTasks;
    var level = 1;
    while (requiredCumulativeForLevel(level + 1) <= count) {
      level++;
    }
    return level;
  }

  /// レベル帯に対応する称号。
  static String titleForLevel(int level) {
    var title = titleBands.first.title;
    for (final band in titleBands) {
      if (level >= band.minLevel) title = band.title;
    }
    return title;
  }

  /// 累計タスク数から、現在レベル・称号・次レベルまでの進捗をまとめて算出する。
  static LevelProgress progressFor(int cumulativeTasks) {
    final count = cumulativeTasks < 0 ? 0 : cumulativeTasks;
    final level = levelForCumulative(count);
    final floor = requiredCumulativeForLevel(level);
    final next = requiredCumulativeForLevel(level + 1);
    final span = next - floor;
    final into = count - floor;
    final remaining = (next - count).clamp(0, next);
    final fraction = span <= 0 ? 1.0 : (into / span).clamp(0.0, 1.0).toDouble();
    return LevelProgress(
      level: level,
      title: titleForLevel(level),
      cumulativeTasks: count,
      currentLevelFloor: floor,
      nextLevelRequirement: next,
      tasksIntoLevel: into,
      tasksForNextLevel: span,
      remainingToNext: remaining,
      fraction: fraction,
    );
  }
}

/// ルーレットの4区分。盤面の7マスはこの区分を演出として割り当てたもので、
/// 確率の本体はこの4区分の重みで持つ（仕様2.3）。
enum RouletteCategory { jackpot, chu, sho, miss }

extension RouletteCategoryX on RouletteCategory {
  /// 表示用ラベル。ハズレは罰に見せないニアミス表現にする（ゲーミフィケーションレビュー反映）。
  String get label => switch (this) {
    RouletteCategory.jackpot => '大当たり',
    RouletteCategory.chu => '中当たり',
    RouletteCategory.sho => '小当たり',
    RouletteCategory.miss => 'ニアミス',
  };

  /// 当選（大/中/小）か。ハズレのみ false。
  bool get isWin => this != RouletteCategory.miss;

  /// チケットとしてバンク（在庫化）する区分か。小は「即時許可」でバンクしない
  /// （週多数発生で氾濫・死蔵を避けるため。ゲーミフィケーションレビュー反映）。
  bool get banksTicket =>
      this == RouletteCategory.jackpot || this == RouletteCategory.chu;
}

/// 4区分の確率。合計は 1.0。
class RouletteProbabilities {
  const RouletteProbabilities({
    required this.jackpot,
    required this.chu,
    required this.sho,
    required this.miss,
    required this.jackpotClamped,
    required this.chuClamped,
    required this.shoClamped,
  });

  final double jackpot;
  final double chu;
  final double sho;
  final double miss;

  /// J/W が [RewardConfig.jackpotCap] を超えてクランプされたか（設定画面で警告表示）。
  final bool jackpotClamped;
  final bool chuClamped;
  final bool shoClamped;

  double probabilityOf(RouletteCategory category) => switch (category) {
    RouletteCategory.jackpot => jackpot,
    RouletteCategory.chu => chu,
    RouletteCategory.sho => sho,
    RouletteCategory.miss => miss,
  };

  double get total => jackpot + chu + sho + miss;
}

/// 盤面1マスの構成。
class RouletteCell {
  const RouletteCell(this.category, this.sweepFraction);

  final RouletteCategory category;

  /// 円全体（1.0）に対するこのマスの角度割合。
  final double sweepFraction;
}

/// 称号バンドの1区切り。
class TitleBand {
  const TitleBand({required this.minLevel, required this.title});

  final int minLevel;
  final String title;
}

/// 現在レベル・称号・次レベルまでの進捗。
class LevelProgress {
  const LevelProgress({
    required this.level,
    required this.title,
    required this.cumulativeTasks,
    required this.currentLevelFloor,
    required this.nextLevelRequirement,
    required this.tasksIntoLevel,
    required this.tasksForNextLevel,
    required this.remainingToNext,
    required this.fraction,
  });

  /// 現在レベル。
  final int level;

  /// 現在レベルの称号。
  final String title;

  /// 累計タスク達成数。
  final int cumulativeTasks;

  /// 現在レベル到達に必要だった累計数 C(level)。
  final int currentLevelFloor;

  /// 次レベル到達に必要な累計数 C(level+1)。
  final int nextLevelRequirement;

  /// 現在レベル内ですでに進んだタスク数（cumulativeTasks - C(level)）。
  final int tasksIntoLevel;

  /// 現在レベルから次レベルまでに必要なタスク数（C(level+1) - C(level)）。
  final int tasksForNextLevel;

  /// 次レベルまであと何タスクか。
  final int remainingToNext;

  /// 次レベルまでの進捗（0.0〜1.0）。プログレスバー用。
  final double fraction;
}
