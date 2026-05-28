import 'package:cloud_firestore/cloud_firestore.dart';

class UserSettings {
  const UserSettings({
    this.displayName = '',
    this.avatarUrl = '',
    this.level = 1,
    this.monthlyBudget = 0,
    this.monthlyQuestDays = 0,
    this.dailyQuestMinutes = 0,
    this.totalEarned = 0,
    this.mealGoalGrams = 0,
    this.exerciseGoalMinutes = 0,
    this.sleepGoalHours = 0,
    this.sleepGoalMinutesExtra = 0,
    this.meditationGoalMinutes = 0,
    this.themeMode = 'system',
    this.weekStartDay = DateTime.monday,
  });

  final String displayName;
  final String avatarUrl;
  final int level;
  final int monthlyBudget;
  final int monthlyQuestDays;
  final int dailyQuestMinutes;
  final int totalEarned;
  final int mealGoalGrams;
  final int exerciseGoalMinutes;
  final int sleepGoalHours;
  final int sleepGoalMinutesExtra;
  final int meditationGoalMinutes;
  /// 'system' | 'light' | 'dark'
  final String themeMode;
  /// DateTime.monday(1) | DateTime.sunday(7) | DateTime.saturday(6)
  final int weekStartDay;

  double get hourlyRate {
    final totalMinutes = monthlyQuestDays * dailyQuestMinutes;
    if (totalMinutes <= 0) return 0;
    return monthlyBudget / (totalMinutes / 60);
  }

  UserSettings copyWith({
    String? displayName,
    String? avatarUrl,
    int? level,
    int? monthlyBudget,
    int? monthlyQuestDays,
    int? dailyQuestMinutes,
    int? totalEarned,
    int? mealGoalGrams,
    int? exerciseGoalMinutes,
    int? sleepGoalHours,
    int? sleepGoalMinutesExtra,
    int? meditationGoalMinutes,
    String? themeMode,
    int? weekStartDay,
  }) {
    return UserSettings(
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      level: level ?? this.level,
      monthlyBudget: monthlyBudget ?? this.monthlyBudget,
      monthlyQuestDays: monthlyQuestDays ?? this.monthlyQuestDays,
      dailyQuestMinutes: dailyQuestMinutes ?? this.dailyQuestMinutes,
      totalEarned: totalEarned ?? this.totalEarned,
      mealGoalGrams: mealGoalGrams ?? this.mealGoalGrams,
      exerciseGoalMinutes: exerciseGoalMinutes ?? this.exerciseGoalMinutes,
      sleepGoalHours: sleepGoalHours ?? this.sleepGoalHours,
      sleepGoalMinutesExtra: sleepGoalMinutesExtra ?? this.sleepGoalMinutesExtra,
      meditationGoalMinutes: meditationGoalMinutes ?? this.meditationGoalMinutes,
      themeMode: themeMode ?? this.themeMode,
      weekStartDay: weekStartDay ?? this.weekStartDay,
    );
  }

  factory UserSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserSettings(
      displayName: data['displayName'] as String? ?? '',
      avatarUrl: data['avatarUrl'] as String? ?? '',
      level: (data['level'] as num?)?.toInt() ?? 1,
      monthlyBudget: (data['monthlyBudget'] as num?)?.toInt() ?? 0,
      monthlyQuestDays: (data['monthlyQuestDays'] as num?)?.toInt() ?? 0,
      dailyQuestMinutes: (data['dailyQuestMinutes'] as num?)?.toInt() ?? 0,
      totalEarned: (data['totalEarned'] as num?)?.toInt() ?? 0,
      mealGoalGrams: (data['mealGoalGrams'] as num?)?.toInt() ?? 0,
      exerciseGoalMinutes: (data['exerciseGoalMinutes'] as num?)?.toInt() ?? 0,
      sleepGoalHours: (data['sleepGoalHours'] as num?)?.toInt() ?? 0,
      sleepGoalMinutesExtra: (data['sleepGoalMinutesExtra'] as num?)?.toInt() ?? 0,
      meditationGoalMinutes: (data['meditationGoalMinutes'] as num?)?.toInt() ?? 0,
      themeMode: data['themeMode'] as String? ?? 'system',
      weekStartDay: (data['weekStartDay'] as num?)?.toInt() ?? DateTime.monday,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'level': level,
      'monthlyBudget': monthlyBudget,
      'monthlyQuestDays': monthlyQuestDays,
      'dailyQuestMinutes': dailyQuestMinutes,
      'totalEarned': totalEarned,
      'hourlyRate': hourlyRate,
      'mealGoalGrams': mealGoalGrams,
      'exerciseGoalMinutes': exerciseGoalMinutes,
      'sleepGoalHours': sleepGoalHours,
      'sleepGoalMinutesExtra': sleepGoalMinutesExtra,
      'meditationGoalMinutes': meditationGoalMinutes,
      'themeMode': themeMode,
      'weekStartDay': weekStartDay,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
