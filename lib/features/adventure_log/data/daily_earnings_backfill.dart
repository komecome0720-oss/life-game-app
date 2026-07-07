import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:task_manager/features/adventure_log/model/adventure_log_entry.dart';
import 'package:task_manager/features/adventure_log/model/daily_earning.dart';

/// `adventure_entries` 全件から `daily_earnings` を再構築するバックフィル。
///
/// 上書き `set()` にする理由: increment 経路で書かれた分があっても、元の
/// adventure_entries から再計算するため自己修復される（読取〜書込の数秒の
/// レースは個人アプリとして許容する）。
class DailyEarningsBackfill {
  DailyEarningsBackfill({FirebaseFirestore? db, FirebaseAuth? auth})
    : _db = db ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  static const _backfillMarkerKey = 'dailyEarningsBackfillV1CompletedAtUtc';

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  Future<void>? _backfillFuture;

  Future<void> backfillIfNeeded() {
    final running = _backfillFuture;
    if (running != null) return running;

    final future = _backfillIfNeeded();
    _backfillFuture = future;
    return future.whenComplete(() {
      if (identical(_backfillFuture, future)) {
        _backfillFuture = null;
      }
    });
  }

  Future<void> _backfillIfNeeded() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final userRef = _db.collection('users').doc(uid);
    final userDoc = await userRef.get();
    if (userDoc.data()?[_backfillMarkerKey] != null) return;

    final entriesSnap = await userRef
        .collection('adventure_entries')
        .orderBy('occurredAtUtc')
        .get();

    final totalsByDateKey = <String, _DayTotals>{};
    for (final doc in entriesSnap.docs) {
      final entry = AdventureLogEntry.fromFirestore(doc);
      final occurredAt = entry.occurredAt;
      if (occurredAt == null) continue;
      final field = _fieldFor(entry.type);
      if (field == null) continue;

      final key = formatDateKey(
        DateTime(occurredAt.year, occurredAt.month, occurredAt.day),
      );
      totalsByDateKey.putIfAbsent(key, _DayTotals.new).add(field, entry.deltaYen);
    }

    var batch = _db.batch();
    var opCount = 0;
    Future<void> commitBatch() async {
      if (opCount == 0) return;
      await batch.commit();
      batch = _db.batch();
      opCount = 0;
    }

    for (final entry in totalsByDateKey.entries) {
      if (opCount >= 450) {
        await commitBatch();
      }
      final dayRef = userRef.collection('daily_earnings').doc(entry.key);
      batch.set(dayRef, {
        'taskYen': entry.value.taskYen,
        'healthYen': entry.value.healthYen,
        'manualYen': entry.value.manualYen,
        'updatedAtUtc': FieldValue.serverTimestamp(),
      });
      opCount++;
    }

    if (opCount >= 450) {
      await commitBatch();
    }
    batch.set(userRef, {
      _backfillMarkerKey: FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    opCount++;
    await commitBatch();
  }

  String? _fieldFor(AdventureEntryType type) {
    switch (type) {
      case AdventureEntryType.taskCompleted:
      case AdventureEntryType.taskReverted:
        return 'taskYen';
      case AdventureEntryType.healthAdjusted:
        return 'healthYen';
      case AdventureEntryType.manualAdjusted:
        return 'manualYen';
      case AdventureEntryType.wishPurchased:
      case AdventureEntryType.wishUnpurchased:
        return null;
    }
  }
}

class _DayTotals {
  int taskYen = 0;
  int healthYen = 0;
  int manualYen = 0;

  void add(String field, int delta) {
    switch (field) {
      case 'taskYen':
        taskYen += delta;
        break;
      case 'healthYen':
        healthYen += delta;
        break;
      case 'manualYen':
        manualYen += delta;
        break;
    }
  }
}
