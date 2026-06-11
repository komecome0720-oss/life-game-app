import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:task_manager/features/wish_list/model/wish_item.dart';
import 'package:task_manager/models/calendar_task.dart';

enum AdventureEntryType {
  taskCompleted,
  taskReverted,
  wishPurchased,
  wishUnpurchased,
  healthAdjusted,
  manualAdjusted,
}

extension AdventureEntryTypeX on AdventureEntryType {
  String get wireName => name;

  String get label {
    switch (this) {
      case AdventureEntryType.taskCompleted:
        return 'タスク達成';
      case AdventureEntryType.taskReverted:
        return '達成取り消し';
      case AdventureEntryType.wishPurchased:
        return '商品獲得';
      case AdventureEntryType.wishUnpurchased:
        return '獲得取り消し';
      case AdventureEntryType.healthAdjusted:
        return '健康ボーナス';
      case AdventureEntryType.manualAdjusted:
        return '手動調整';
    }
  }

  IconData get icon {
    switch (this) {
      case AdventureEntryType.taskCompleted:
        return Icons.check_circle_outline;
      case AdventureEntryType.taskReverted:
        return Icons.undo;
      case AdventureEntryType.wishPurchased:
        return Icons.card_giftcard;
      case AdventureEntryType.wishUnpurchased:
        return Icons.replay;
      case AdventureEntryType.healthAdjusted:
        return Icons.monitor_heart_outlined;
      case AdventureEntryType.manualAdjusted:
        return Icons.tune;
    }
  }

  static AdventureEntryType parse(String? value) {
    return AdventureEntryType.values.firstWhere(
      (type) => type.wireName == value,
      orElse: () => AdventureEntryType.manualAdjusted,
    );
  }
}

class AdventureLogEntry {
  const AdventureLogEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.deltaYen,
    this.sourceId,
    this.balanceBeforeYen,
    this.balanceAfterYen,
    this.occurredAt,
    this.createdAt,
    this.isLegacyEstimate = false,
    this.note,
  });

  final String id;
  final AdventureEntryType type;
  final String? sourceId;
  final String title;
  final int deltaYen;
  final int? balanceBeforeYen;
  final int? balanceAfterYen;
  final DateTime? occurredAt;
  final DateTime? createdAt;
  final bool isLegacyEstimate;
  final String? note;

  DateTime get sortAt =>
      occurredAt ??
      createdAt ??
      DateTime.fromMillisecondsSinceEpoch(0);

  bool get affectsChart =>
      !isLegacyEstimate && balanceBeforeYen != null && balanceAfterYen != null;

  factory AdventureLogEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    DateTime? ts(Object? value) =>
        value is Timestamp ? value.toDate().toLocal() : null;
    return AdventureLogEntry(
      id: doc.id,
      type: AdventureEntryTypeX.parse(data['type'] as String?),
      sourceId: data['sourceId'] as String?,
      title: data['title'] as String? ?? '',
      deltaYen: (data['deltaYen'] as num?)?.toInt() ?? 0,
      balanceBeforeYen: (data['balanceBeforeYen'] as num?)?.toInt(),
      balanceAfterYen: (data['balanceAfterYen'] as num?)?.toInt(),
      occurredAt: ts(data['occurredAtUtc']),
      createdAt: ts(data['createdAtUtc']),
      isLegacyEstimate: data['isLegacyEstimate'] as bool? ?? false,
      note: data['note'] as String?,
    );
  }

  factory AdventureLogEntry.legacyTask(CalendarTask task) {
    final reward = task.rewardYen;
    return AdventureLogEntry(
      id: 'legacy-task-${task.id}',
      type: AdventureEntryType.taskCompleted,
      sourceId: task.id,
      title: task.title,
      deltaYen: reward,
      occurredAt: task.completedAt,
      isLegacyEstimate: true,
      note: reward == 0 ? '過去データのため獲得額未記録' : '過去データから推定',
    );
  }

  factory AdventureLogEntry.legacyWish(WishItem item) {
    return AdventureLogEntry(
      id: 'legacy-wish-${item.id}',
      type: AdventureEntryType.wishPurchased,
      sourceId: item.id,
      title: item.name,
      deltaYen: -item.price,
      occurredAt: item.createdAt,
      isLegacyEstimate: true,
      note: item.createdAtWasMissing ? '獲得日時未記録' : '獲得日時未記録・作成日で表示',
    );
  }
}
