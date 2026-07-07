import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:task_manager/features/roulette/model/reward_config.dart';

class UserSettings {
  /// ToDo新規作成時の見込時間デフォルト（分）。
  static const int defaultTodoEstimatedMinutesFallback = 30;

  /// カレンダー新規タスク作成時の所要時間デフォルト（分）。
  static const int defaultCalendarDurationMinutesFallback = 60;

  const UserSettings({
    this.displayName = '',
    this.avatarUrl = '',
    this.monthlyBudget = 0,
    this.monthlyQuestDays = 0,
    this.dailyQuestMinutes = 0,
    this.totalEarned = 0,
    this.cumulativeTaskCount = 0,
    this.weeklyTaskCount = RewardConfig.defaultWeeklyTaskCount,
    this.weeklyJackpotCount = RewardConfig.defaultWeeklyJackpotCount,
    this.weeklyChuCount = RewardConfig.defaultWeeklyChuCount,
    this.weeklyShoCount = RewardConfig.defaultWeeklyShoCount,
    this.jackpotRewards = RewardConfig.defaultJackpotRewards,
    this.chuRewards = RewardConfig.defaultChuRewards,
    this.shoRewards = RewardConfig.defaultShoRewards,
    this.mealGoalGrams = 0,
    this.exerciseGoalMinutes = 0,
    this.sleepGoalHours = 0,
    this.sleepGoalMinutesExtra = 0,
    this.meditationGoalMinutes = 0,
    this.themeMode = 'system',
    this.weekStartDay = DateTime.monday,
    this.defaultTodoEstimatedMinutes = defaultTodoEstimatedMinutesFallback,
    this.defaultCalendarDurationMinutes = defaultCalendarDurationMinutesFallback,
    this.onboardingCompleted = false,
  });

  final String displayName;
  final String avatarUrl;
  final int monthlyBudget;
  final int monthlyQuestDays;
  final int dailyQuestMinutes;
  final int totalEarned;

  /// 累計タスク達成数（レベル算出のソース）。
  /// `EconomyRepository.completeTask` のトランザクションが所有して増減するため、
  /// **[toFirestore] には含めない**（設定保存の merge で stale 値に上書きしないため）。
  final int cumulativeTaskCount;

  // --- ルーレット設定（このモデル＝設定保存側が所有。完了トランザクションは触れない）---
  /// 週あたりのタスク予定回数 (W)。
  final double weeklyTaskCount;

  /// 週に欲しい大当たり回数 (J)。
  final double weeklyJackpotCount;

  /// 週に欲しい中当たり回数 (C)。
  final double weeklyChuCount;

  /// 週に欲しい小当たり回数 (S)。
  final double weeklyShoCount;

  /// 大／中／小それぞれのご褒美内容リスト。
  final List<String> jackpotRewards;
  final List<String> chuRewards;
  final List<String> shoRewards;

  final int mealGoalGrams;
  final int exerciseGoalMinutes;
  final int sleepGoalHours;
  final int sleepGoalMinutesExtra;
  final int meditationGoalMinutes;

  /// 'system' | 'light' | 'dark'
  final String themeMode;

  /// DateTime.monday(1) | DateTime.sunday(7) | DateTime.saturday(6)
  final int weekStartDay;

  /// ToDo新規作成時の見込時間デフォルト（分）。
  final int defaultTodoEstimatedMinutes;

  /// カレンダー新規タスク作成時の所要時間デフォルト（分）。
  final int defaultCalendarDurationMinutes;

  /// オンボーディング（初回チュートリアル）を完了済みか。
  /// `OnboardingGate` がコーチマーク終了時に部分保存で所有するフィールドのため、
  /// **[toFirestore] には含めない**（cumulativeTaskCount と同じ規約。ウィザードや
  /// 設定画面の全体保存でこのフラグを stale 値に巻き戻さないため）。
  final bool onboardingCompleted;

  double get hourlyRate {
    final totalMinutes = monthlyQuestDays * dailyQuestMinutes;
    if (totalMinutes <= 0) return 0;
    return monthlyBudget / (totalMinutes / 60);
  }

  /// 現在レベル（累計タスク数から導出。手入力ではない）。
  int get level => RewardConfig.levelForCumulative(cumulativeTaskCount);

  /// 現在レベル・称号・次レベルまでの進捗。
  LevelProgress get levelProgress =>
      RewardConfig.progressFor(cumulativeTaskCount);

  /// 区分ごとのご褒美リスト。
  List<String> rewardsFor(RouletteCategory tier) => switch (tier) {
    RouletteCategory.jackpot => jackpotRewards,
    RouletteCategory.chu => chuRewards,
    RouletteCategory.sho => shoRewards,
    RouletteCategory.miss => const [],
  };

  UserSettings copyWith({
    String? displayName,
    String? avatarUrl,
    int? monthlyBudget,
    int? monthlyQuestDays,
    int? dailyQuestMinutes,
    int? totalEarned,
    int? cumulativeTaskCount,
    double? weeklyTaskCount,
    double? weeklyJackpotCount,
    double? weeklyChuCount,
    double? weeklyShoCount,
    List<String>? jackpotRewards,
    List<String>? chuRewards,
    List<String>? shoRewards,
    int? mealGoalGrams,
    int? exerciseGoalMinutes,
    int? sleepGoalHours,
    int? sleepGoalMinutesExtra,
    int? meditationGoalMinutes,
    String? themeMode,
    int? weekStartDay,
    int? defaultTodoEstimatedMinutes,
    int? defaultCalendarDurationMinutes,
    bool? onboardingCompleted,
  }) {
    return UserSettings(
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      monthlyBudget: monthlyBudget ?? this.monthlyBudget,
      monthlyQuestDays: monthlyQuestDays ?? this.monthlyQuestDays,
      dailyQuestMinutes: dailyQuestMinutes ?? this.dailyQuestMinutes,
      totalEarned: totalEarned ?? this.totalEarned,
      cumulativeTaskCount: cumulativeTaskCount ?? this.cumulativeTaskCount,
      weeklyTaskCount: weeklyTaskCount ?? this.weeklyTaskCount,
      weeklyJackpotCount: weeklyJackpotCount ?? this.weeklyJackpotCount,
      weeklyChuCount: weeklyChuCount ?? this.weeklyChuCount,
      weeklyShoCount: weeklyShoCount ?? this.weeklyShoCount,
      jackpotRewards: jackpotRewards ?? this.jackpotRewards,
      chuRewards: chuRewards ?? this.chuRewards,
      shoRewards: shoRewards ?? this.shoRewards,
      mealGoalGrams: mealGoalGrams ?? this.mealGoalGrams,
      exerciseGoalMinutes: exerciseGoalMinutes ?? this.exerciseGoalMinutes,
      sleepGoalHours: sleepGoalHours ?? this.sleepGoalHours,
      sleepGoalMinutesExtra:
          sleepGoalMinutesExtra ?? this.sleepGoalMinutesExtra,
      meditationGoalMinutes:
          meditationGoalMinutes ?? this.meditationGoalMinutes,
      themeMode: themeMode ?? this.themeMode,
      weekStartDay: weekStartDay ?? this.weekStartDay,
      defaultTodoEstimatedMinutes:
          defaultTodoEstimatedMinutes ?? this.defaultTodoEstimatedMinutes,
      defaultCalendarDurationMinutes:
          defaultCalendarDurationMinutes ?? this.defaultCalendarDurationMinutes,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    );
  }

  static List<String> _rewardsFromData(Object? raw, List<String> fallback) {
    if (raw is! List) return fallback; // キー未設定なら初期シードを使う
    return raw.map((e) => e.toString()).toList();
  }

  factory UserSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final weeklyTaskCount =
        (data['weeklyTaskCount'] as num?)?.toDouble() ??
        RewardConfig.defaultWeeklyTaskCount;
    final weeklyJackpotCount =
        (data['weeklyJackpotCount'] as num?)?.toDouble() ??
        RewardConfig.defaultWeeklyJackpotCount;
    final weeklyChuCount =
        (data['weeklyChuCount'] as num?)?.toDouble() ??
        RewardConfig.legacyWeeklyChuCountFor(
          weeklyTaskCount: weeklyTaskCount,
          weeklyJackpotCount: weeklyJackpotCount,
        );
    return UserSettings(
      displayName: data['displayName'] as String? ?? '',
      avatarUrl: data['avatarUrl'] as String? ?? '',
      monthlyBudget: (data['monthlyBudget'] as num?)?.toInt() ?? 0,
      monthlyQuestDays: (data['monthlyQuestDays'] as num?)?.toInt() ?? 0,
      dailyQuestMinutes: (data['dailyQuestMinutes'] as num?)?.toInt() ?? 0,
      totalEarned: (data['totalEarned'] as num?)?.toInt() ?? 0,
      cumulativeTaskCount: (data['cumulativeTaskCount'] as num?)?.toInt() ?? 0,
      weeklyTaskCount: weeklyTaskCount,
      weeklyJackpotCount: weeklyJackpotCount,
      weeklyChuCount: weeklyChuCount,
      weeklyShoCount:
          (data['weeklyShoCount'] as num?)?.toDouble() ??
          RewardConfig.legacyWeeklyShoCountFor(
            weeklyTaskCount: weeklyTaskCount,
            weeklyJackpotCount: weeklyJackpotCount,
            weeklyChuCount: weeklyChuCount,
          ),
      jackpotRewards: _rewardsFromData(
        data['jackpotRewards'],
        RewardConfig.defaultJackpotRewards,
      ),
      chuRewards: _rewardsFromData(
        data['chuRewards'],
        RewardConfig.defaultChuRewards,
      ),
      shoRewards: _rewardsFromData(
        data['shoRewards'],
        RewardConfig.defaultShoRewards,
      ),
      mealGoalGrams: (data['mealGoalGrams'] as num?)?.toInt() ?? 0,
      exerciseGoalMinutes: (data['exerciseGoalMinutes'] as num?)?.toInt() ?? 0,
      sleepGoalHours: (data['sleepGoalHours'] as num?)?.toInt() ?? 0,
      sleepGoalMinutesExtra:
          (data['sleepGoalMinutesExtra'] as num?)?.toInt() ?? 0,
      meditationGoalMinutes:
          (data['meditationGoalMinutes'] as num?)?.toInt() ?? 0,
      themeMode: data['themeMode'] as String? ?? 'system',
      weekStartDay: (data['weekStartDay'] as num?)?.toInt() ?? DateTime.monday,
      defaultTodoEstimatedMinutes:
          (data['defaultTodoEstimatedMinutes'] as num?)?.toInt() ??
              defaultTodoEstimatedMinutesFallback,
      defaultCalendarDurationMinutes:
          (data['defaultCalendarDurationMinutes'] as num?)?.toInt() ??
              defaultCalendarDurationMinutesFallback,
      onboardingCompleted: data['onboardingCompleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    // 注意: `cumulativeTaskCount` は完了トランザクションが所有するため、ここには含めない。
    // 注意: `onboardingCompleted` は OnboardingGate の部分保存が所有するため、ここには含めない
    // （ウィザードや設定画面での全体保存がフラグを stale 値に巻き戻さないようにするため）。
    return {
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'monthlyBudget': monthlyBudget,
      'monthlyQuestDays': monthlyQuestDays,
      'dailyQuestMinutes': dailyQuestMinutes,
      'totalEarned': totalEarned,
      'hourlyRate': hourlyRate,
      'weeklyTaskCount': weeklyTaskCount,
      'weeklyJackpotCount': weeklyJackpotCount,
      'weeklyChuCount': weeklyChuCount,
      'weeklyShoCount': weeklyShoCount,
      'jackpotRewards': jackpotRewards,
      'chuRewards': chuRewards,
      'shoRewards': shoRewards,
      'mealGoalGrams': mealGoalGrams,
      'exerciseGoalMinutes': exerciseGoalMinutes,
      'sleepGoalHours': sleepGoalHours,
      'sleepGoalMinutesExtra': sleepGoalMinutesExtra,
      'meditationGoalMinutes': meditationGoalMinutes,
      'themeMode': themeMode,
      'weekStartDay': weekStartDay,
      'defaultTodoEstimatedMinutes': defaultTodoEstimatedMinutes,
      'defaultCalendarDurationMinutes': defaultCalendarDurationMinutes,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
