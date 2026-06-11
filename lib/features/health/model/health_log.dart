import 'package:cloud_firestore/cloud_firestore.dart';

/// 1日分の健康ログ。Firestore: users/{uid}/healthLogs/{yyyy-MM-dd}
class HealthLog {
  const HealthLog({
    required this.dateKey,
    this.mealGrams = 0.0,
    this.exerciseMinutes = 0.0,
    this.sleepMinutes = 0.0,
    this.meditationMinutes = 0.0,
    this.mealScore = 0,
    this.sleepScore = 0,
    this.exerciseScore = 0,
    this.meditationScore = 0,
    this.totalScore = 0,
    this.provisionalEarnedYen = 0,
    this.finalizedEarnedYen = 0,
    this.isFinalized = false,
    this.updatedAt,
    this.finalizedAt,
  });

  final String dateKey;
  final double mealGrams;
  final double exerciseMinutes;
  final double sleepMinutes;
  final double meditationMinutes;

  /// 重み付き点数（食事・睡眠は max30、運動・瞑想は max20）
  final int mealScore;
  final int sleepScore;
  final int exerciseScore;
  final int meditationScore;

  /// 合計（0〜100）
  final int totalScore;

  final int provisionalEarnedYen;
  final int finalizedEarnedYen;
  final bool isFinalized;

  final DateTime? updatedAt;
  final DateTime? finalizedAt;

  HealthLog copyWith({
    String? dateKey,
    double? mealGrams,
    double? exerciseMinutes,
    double? sleepMinutes,
    double? meditationMinutes,
    int? mealScore,
    int? sleepScore,
    int? exerciseScore,
    int? meditationScore,
    int? totalScore,
    int? provisionalEarnedYen,
    int? finalizedEarnedYen,
    bool? isFinalized,
    DateTime? updatedAt,
    DateTime? finalizedAt,
  }) {
    return HealthLog(
      dateKey: dateKey ?? this.dateKey,
      mealGrams: mealGrams ?? this.mealGrams,
      exerciseMinutes: exerciseMinutes ?? this.exerciseMinutes,
      sleepMinutes: sleepMinutes ?? this.sleepMinutes,
      meditationMinutes: meditationMinutes ?? this.meditationMinutes,
      mealScore: mealScore ?? this.mealScore,
      sleepScore: sleepScore ?? this.sleepScore,
      exerciseScore: exerciseScore ?? this.exerciseScore,
      meditationScore: meditationScore ?? this.meditationScore,
      totalScore: totalScore ?? this.totalScore,
      provisionalEarnedYen: provisionalEarnedYen ?? this.provisionalEarnedYen,
      finalizedEarnedYen: finalizedEarnedYen ?? this.finalizedEarnedYen,
      isFinalized: isFinalized ?? this.isFinalized,
      updatedAt: updatedAt ?? this.updatedAt,
      finalizedAt: finalizedAt ?? this.finalizedAt,
    );
  }

  factory HealthLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    DateTime? ts(Object? v) => v is Timestamp ? v.toDate() : null;
    double decimal(Object? v) => (v as num?)?.toDouble() ?? 0.0;
    return HealthLog(
      dateKey: data['dateKey'] as String? ?? doc.id,
      mealGrams: decimal(data['mealGrams']),
      exerciseMinutes: decimal(data['exerciseMinutes']),
      sleepMinutes: decimal(data['sleepMinutes']),
      meditationMinutes: decimal(data['meditationMinutes']),
      mealScore: (data['mealScore'] as num?)?.toInt() ?? 0,
      sleepScore: (data['sleepScore'] as num?)?.toInt() ?? 0,
      exerciseScore: (data['exerciseScore'] as num?)?.toInt() ?? 0,
      meditationScore: (data['meditationScore'] as num?)?.toInt() ?? 0,
      totalScore: (data['totalScore'] as num?)?.toInt() ?? 0,
      provisionalEarnedYen:
          (data['provisionalEarnedYen'] as num?)?.toInt() ?? 0,
      finalizedEarnedYen: (data['finalizedEarnedYen'] as num?)?.toInt() ?? 0,
      isFinalized: data['isFinalized'] as bool? ?? false,
      updatedAt: ts(data['updatedAt']),
      finalizedAt: ts(data['finalizedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'dateKey': dateKey,
      'mealGrams': mealGrams,
      'exerciseMinutes': exerciseMinutes,
      'sleepMinutes': sleepMinutes,
      'meditationMinutes': meditationMinutes,
      'mealScore': mealScore,
      'sleepScore': sleepScore,
      'exerciseScore': exerciseScore,
      'meditationScore': meditationScore,
      'totalScore': totalScore,
      'provisionalEarnedYen': provisionalEarnedYen,
      'finalizedEarnedYen': finalizedEarnedYen,
      'isFinalized': isFinalized,
      'updatedAt': FieldValue.serverTimestamp(),
      if (finalizedAt != null) 'finalizedAt': Timestamp.fromDate(finalizedAt!),
    };
  }
}
