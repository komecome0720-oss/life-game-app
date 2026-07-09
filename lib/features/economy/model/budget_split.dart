// 月予算の70/30分割・健康報酬ゲート・ストリークフリーズ等の政策定数。
//
// 詳細仕様: `obsidian/10_Project/健康管理報酬リデザイン仕様_2026-07-09.md`

/// タスク側の予算配分比率（時間単価に掛ける）。
const double kTaskBudgetRatio = 0.70;

/// 健康側の月間予算配分比率。
const double kHealthBudgetRatio = 0.30;

/// 健康デイリーキャップ算出時の分母（固定30日）。
const int kHealthCapDays = 30;

/// 健康報酬の没収ライン（達成率）。これ未満は0円。
const double kHealthGateRatio = 0.40;

/// ストリーク成立ライン（達成率）。
const double kHealthStreakRatio = 0.80;

/// 健康スコアゲージの区切り線（達成率）。
const List<double> kHealthGaugeRatios = [0.40, 0.60, 0.80];

/// 月初に付与されるフリーズ個数（繰り越しなし）。
const int kFreezeMonthlyGrant = 2;

/// フリーズの同時保有上限。
const int kFreezeMax = 5;

/// ストリーク称号ランクアップの節目日数。
const List<int> kStreakMilestones = [3, 7, 14, 30, 60, 100];

/// 節目日数に対応する称号名（仕様§7-2の既定案）。
const Map<int, String> kStreakTitles = {
  3: '習慣の芽',
  7: '一週間の勇者',
  14: '二週間の達人',
  30: '一ヶ月の賢者',
  60: '不屈の求道者',
  100: '健康の化身',
};

/// [count] 日目に到達した際の称号名。節目でなければ null。
String? streakTitleForCount(int count) => kStreakTitles[count];
