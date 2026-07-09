import 'package:cloud_firestore/cloud_firestore.dart';

/// ストリーク（連続達成）状態。
/// 保存先 `users/{uid}/healthState/streak`（doc id 固定）。非現金（称号＋フリーズのみ）。
class HealthStreakState {
  const HealthStreakState({
    this.streakCount = 0,
    this.lastQualifiedDateKey,
    this.lastProcessedDateKey,
    this.freezesRemaining = 0,
    this.freezeMonthKey,
    this.achievedTitles = const [],
  });

  /// 現在の連続達成日数。
  final int streakCount;

  /// 最後に p >= 0.80（ストリーク成立ライン）を満たした日の dateKey。
  final String? lastQualifiedDateKey;

  /// ストリークエンジンが前進済みの最終カレンダー日（dateKey）。
  /// 冪等な前進のために使う：これより前は再処理しない。
  final String? lastProcessedDateKey;

  /// 保有フリーズ数（0〜[kFreezeMax]）。
  final int freezesRemaining;

  /// フリーズを最後に付与した月（'yyyy-MM'）。月替りでフリーズを繰り越しなしで再付与する判定に使う。
  final String? freezeMonthKey;

  /// これまでに到達した節目称号名（[streakTitleForCount]）の一覧。
  final List<String> achievedTitles;

  HealthStreakState copyWith({
    int? streakCount,
    Object? lastQualifiedDateKey = _unset,
    Object? lastProcessedDateKey = _unset,
    int? freezesRemaining,
    Object? freezeMonthKey = _unset,
    List<String>? achievedTitles,
  }) {
    return HealthStreakState(
      streakCount: streakCount ?? this.streakCount,
      lastQualifiedDateKey: identical(lastQualifiedDateKey, _unset)
          ? this.lastQualifiedDateKey
          : lastQualifiedDateKey as String?,
      lastProcessedDateKey: identical(lastProcessedDateKey, _unset)
          ? this.lastProcessedDateKey
          : lastProcessedDateKey as String?,
      freezesRemaining: freezesRemaining ?? this.freezesRemaining,
      freezeMonthKey: identical(freezeMonthKey, _unset)
          ? this.freezeMonthKey
          : freezeMonthKey as String?,
      achievedTitles: achievedTitles ?? this.achievedTitles,
    );
  }

  static const Object _unset = Object();

  factory HealthStreakState.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return HealthStreakState(
      streakCount: (data['streakCount'] as num?)?.toInt() ?? 0,
      lastQualifiedDateKey: data['lastQualifiedDateKey'] as String?,
      lastProcessedDateKey: data['lastProcessedDateKey'] as String?,
      freezesRemaining: (data['freezesRemaining'] as num?)?.toInt() ?? 0,
      freezeMonthKey: data['freezeMonthKey'] as String?,
      achievedTitles:
          (data['achievedTitles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'streakCount': streakCount,
      if (lastQualifiedDateKey != null)
        'lastQualifiedDateKey': lastQualifiedDateKey,
      if (lastProcessedDateKey != null)
        'lastProcessedDateKey': lastProcessedDateKey,
      'freezesRemaining': freezesRemaining,
      if (freezeMonthKey != null) 'freezeMonthKey': freezeMonthKey,
      'achievedTitles': achievedTitles,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
