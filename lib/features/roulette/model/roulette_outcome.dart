import 'package:task_manager/features/roulette/model/reward_config.dart';

/// 1回のルーレット抽選の結果種別。
enum RouletteOutcomeKind {
  /// 当選（大/中/小）。中/大はチケット発行、小は即時許可。
  win,

  /// ハズレ（ニアミス表現。チケットなし）。
  nearMiss,

  /// 当選したが当該区分のご褒美が未設定でフォールバック先も空 → 発行せず設定を促す。
  needsSetup,

  /// W/J 設定が不正で抽選できなかった。
  invalidConfig,
}

/// 1回のルーレット抽選の結果。UI（演出）はこれを受け取って盤面の着地・表示を決める。
class RouletteOutcome {
  const RouletteOutcome._({
    required this.kind,
    this.probabilities,
    this.landedCategory,
    this.tier,
    this.rewardName,
    this.banked = false,
  });

  /// 当選。[tier] はフォールバック適用後の実際の区分、[banked] は中/大でチケット発行したか。
  const RouletteOutcome.win({
    required RouletteProbabilities probabilities,
    required RouletteCategory landedCategory,
    required RouletteCategory tier,
    required String rewardName,
    required bool banked,
  }) : this._(
          kind: RouletteOutcomeKind.win,
          probabilities: probabilities,
          landedCategory: landedCategory,
          tier: tier,
          rewardName: rewardName,
          banked: banked,
        );

  const RouletteOutcome.nearMiss({
    required RouletteProbabilities probabilities,
  }) : this._(
          kind: RouletteOutcomeKind.nearMiss,
          probabilities: probabilities,
          landedCategory: RouletteCategory.miss,
        );

  const RouletteOutcome.needsSetup({
    required RouletteProbabilities probabilities,
    required RouletteCategory landedCategory,
  }) : this._(
          kind: RouletteOutcomeKind.needsSetup,
          probabilities: probabilities,
          landedCategory: landedCategory,
        );

  const RouletteOutcome.invalidConfig()
      : this._(kind: RouletteOutcomeKind.invalidConfig);

  final RouletteOutcomeKind kind;

  /// 盤面描画用の4区分確率（invalidConfig のときのみ null）。
  final RouletteProbabilities? probabilities;

  /// 盤面が着地する区分（演出用）。
  final RouletteCategory? landedCategory;

  /// 実際に付与された区分（フォールバック適用後）。win のときのみ。
  final RouletteCategory? tier;

  /// 当選したご褒美名（win のときのみ）。
  final String? rewardName;

  /// 中/大でチケットを在庫に発行したか。小（即時許可）や他種別では false。
  /// 発行はfire-and-forgetのため、この値は発行の完了・成功までは保証しない。
  final bool banked;

  bool get isWin => kind == RouletteOutcomeKind.win;

  /// 小当たり（当選だがチケット化せず即時許可）か。
  bool get isInstantPermission =>
      kind == RouletteOutcomeKind.win && tier == RouletteCategory.sho;
}
