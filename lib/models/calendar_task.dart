import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum TaskSourceType { manual, googleCalendar }

/// スケジュール表示 + Firestore保存の共通タスクモデル。
/// start/end は端末ローカル時刻で保持し、Firestore保存時にUTC変換する。
///
/// isTodo=true のときはカレンダー非表示の「ToDo（Eisenhower Matrix）」項目として扱い、
/// start/end は null となる。isTodo=false のときはカレンダー予定として扱い start/end は非 null。
@immutable
class CalendarTask {
  const CalendarTask({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.rewardYen,
    this.externalCalendarId,
    this.sourceType = TaskSourceType.manual,
    this.isAllDay = false,
    this.isCompleted = false,
    this.updatedAt,
    this.isTodo = false,
    this.urgency = true,
    this.importance = true,
    this.orderIndex = 0,
    this.note,
    this.estimatedMinutes,
    this.description,
    this.location,
    this.colorId,
    this.recurrence,
    this.recurringEventId,
    this.completedAt,
    this.completedRewardYen,
    this.predictedMinutes,
    this.actualMinutes,
    this.predictionDeclared = false,
  });

  final String id;
  final String title;

  /// 端末ローカル時刻（isTodo=true なら null）
  final DateTime? start;

  /// 端末ローカル時刻（isTodo=true なら null）
  final DateTime? end;
  final int rewardYen;

  /// 重複判定キー: `calendarId:eventId`
  final String? externalCalendarId;
  final TaskSourceType sourceType;
  final bool isAllDay;
  final bool isCompleted;
  final DateTime? updatedAt;

  /// true のとき ToDo マトリクス側に表示。false のときカレンダー側。
  final bool isTodo;

  /// 緊急（true=上段）
  final bool urgency;

  /// 重要（true=右列）
  final bool importance;

  /// 同一象限内での並び順。小さいほど上。
  final int orderIndex;

  /// メモ。詳細シートで編集。
  final String? note;

  /// 予想所要時間（分）
  final int? estimatedMinutes;

  /// 予定の説明（Google: event.description）
  final String? description;

  /// 場所（Google: event.location）
  final String? location;

  /// Google colorId（1〜11、null はカレンダーデフォルト色）
  final String? colorId;

  /// RRULE 文字列の配列。Google 繰り返しイベントに使用。手動タスクも対応予定。
  final List<String>? recurrence;

  /// Google 繰り返しマスターの eventId。単発インスタンスからマスター編集に使う。
  final String? recurringEventId;

  /// 完了時刻（端末ローカル時刻）。未完了なら null。
  final DateTime? completedAt;

  /// 完了時に実際に加算した報酬額。未了戻し時の唯一の減算元。
  final int? completedRewardYen;

  /// 予測時間（分）。完了時にカレンダー枠または手入力から記録される。
  final int? predictedMinutes;

  /// 実績時間（分）。タイマーまたは手入力から記録される。null なら未記録（ログなし完了）。
  final int? actualMinutes;

  /// 予測が宣言済みか。true のときのみ [estimatedMinutes] を精度ゲーム（統計・称号）の対象とする。
  /// デフォルト false（未宣言）。
  final bool predictionDeclared;

  CalendarTask copyWith({
    String? title,
    DateTime? start,
    DateTime? end,
    int? rewardYen,
    String? externalCalendarId,
    TaskSourceType? sourceType,
    bool? isAllDay,
    bool? isCompleted,
    DateTime? updatedAt,
    bool? isTodo,
    bool? urgency,
    bool? importance,
    int? orderIndex,
    String? note,
    int? estimatedMinutes,
    String? description,
    String? location,
    String? colorId,
    List<String>? recurrence,
    String? recurringEventId,
    DateTime? completedAt,
    int? completedRewardYen,
    int? predictedMinutes,
    int? actualMinutes,
    bool? predictionDeclared,
  }) {
    return CalendarTask(
      id: id,
      title: title ?? this.title,
      start: start ?? this.start,
      end: end ?? this.end,
      rewardYen: rewardYen ?? this.rewardYen,
      externalCalendarId: externalCalendarId ?? this.externalCalendarId,
      sourceType: sourceType ?? this.sourceType,
      isAllDay: isAllDay ?? this.isAllDay,
      isCompleted: isCompleted ?? this.isCompleted,
      updatedAt: updatedAt ?? this.updatedAt,
      isTodo: isTodo ?? this.isTodo,
      urgency: urgency ?? this.urgency,
      importance: importance ?? this.importance,
      orderIndex: orderIndex ?? this.orderIndex,
      note: note ?? this.note,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      description: description ?? this.description,
      location: location ?? this.location,
      colorId: colorId ?? this.colorId,
      recurrence: recurrence ?? this.recurrence,
      recurringEventId: recurringEventId ?? this.recurringEventId,
      completedAt: completedAt ?? this.completedAt,
      completedRewardYen: completedRewardYen ?? this.completedRewardYen,
      predictedMinutes: predictedMinutes ?? this.predictedMinutes,
      actualMinutes: actualMinutes ?? this.actualMinutes,
      predictionDeclared: predictionDeclared ?? this.predictionDeclared,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      if (start != null) 'startAtUtc': Timestamp.fromDate(start!.toUtc()),
      if (end != null) 'endAtUtc': Timestamp.fromDate(end!.toUtc()),
      'reward': rewardYen,
      if (externalCalendarId != null) 'externalCalendarId': externalCalendarId,
      'sourceType': sourceType.name,
      'isAllDay': isAllDay,
      'isCompleted': isCompleted,
      'isTodo': isTodo,
      'urgency': urgency,
      'importance': importance,
      'orderIndex': orderIndex,
      if (note != null) 'note': note,
      if (estimatedMinutes != null) 'estimatedMinutes': estimatedMinutes,
      if (description != null) 'description': description,
      if (location != null) 'location': location,
      if (colorId != null) 'colorId': colorId,
      if (recurrence != null) 'recurrence': recurrence,
      if (recurringEventId != null) 'recurringEventId': recurringEventId,
      if (completedAt != null)
        'completedAtUtc': Timestamp.fromDate(completedAt!.toUtc()),
      if (completedRewardYen != null) 'completedRewardYen': completedRewardYen,
      if (predictedMinutes != null) 'predictedMinutes': predictedMinutes,
      if (actualMinutes != null) 'actualMinutes': actualMinutes,
      if (predictionDeclared) 'predictionDeclared': true,
    };
  }

  factory CalendarTask.fromMap(String id, Map<String, dynamic> data) {
    final startTs = data['startAtUtc'] as Timestamp?;
    final endTs = data['endAtUtc'] as Timestamp?;
    return CalendarTask(
      id: id,
      title: data['title'] as String? ?? '',
      start: startTs?.toDate().toLocal(),
      end: endTs?.toDate().toLocal(),
      rewardYen: (data['reward'] as num?)?.toInt() ?? 0,
      externalCalendarId: data['externalCalendarId'] as String?,
      sourceType: TaskSourceType.values.firstWhere(
        (e) => e.name == (data['sourceType'] as String?),
        orElse: () => TaskSourceType.manual,
      ),
      isAllDay: data['isAllDay'] as bool? ?? false,
      isCompleted: data['isCompleted'] as bool? ?? false,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      isTodo: data['isTodo'] as bool? ?? false,
      urgency: data['urgency'] as bool? ?? true,
      importance: data['importance'] as bool? ?? true,
      orderIndex: (data['orderIndex'] as num?)?.toInt() ?? 0,
      note: data['note'] as String?,
      estimatedMinutes: (data['estimatedMinutes'] as num?)?.toInt(),
      description: data['description'] as String?,
      location: data['location'] as String?,
      colorId: data['colorId'] as String?,
      recurrence: (data['recurrence'] as List?)?.whereType<String>().toList(),
      recurringEventId: data['recurringEventId'] as String?,
      completedAt: (data['completedAtUtc'] as Timestamp?)?.toDate().toLocal(),
      completedRewardYen: (data['completedRewardYen'] as num?)?.toInt(),
      predictedMinutes: (data['predictedMinutes'] as num?)?.toInt(),
      actualMinutes: (data['actualMinutes'] as num?)?.toInt(),
      predictionDeclared: data['predictionDeclared'] as bool? ?? false,
    );
  }
}
