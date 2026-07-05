import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:task_manager/features/adventure_log/model/adventure_log_entry.dart';

class BalanceLedgerResult {
  const BalanceLedgerResult({
    required this.applied,
    required this.deltaYen,
    required this.balanceBeforeYen,
    required this.balanceAfterYen,
    this.insufficientFunds = false,
    this.missingAmount = false,
    this.cumulativeTaskCountBefore = 0,
    this.cumulativeTaskCountAfter = 0,
  });

  final bool applied;
  final int deltaYen;
  final int balanceBeforeYen;
  final int balanceAfterYen;
  final bool insufficientFunds;
  final bool missingAmount;

  /// 完了／未了戻しの前後の累計タスク達成数（レベル算出のソース）。
  /// `completeTask` / `revertTask` のみ意味を持つ（他は 0）。
  final int cumulativeTaskCountBefore;
  final int cumulativeTaskCountAfter;
}

class EconomyRepository {
  EconomyRepository({FirebaseFirestore? db, FirebaseAuth? auth})
    : _db = db ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _entriesCol(String uid) =>
      _userRef(uid).collection('adventure_entries');

  int _balanceFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    return (doc.data()?['totalEarned'] as num?)?.toInt() ?? 0;
  }

  int _cumulativeFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    return (doc.data()?['cumulativeTaskCount'] as num?)?.toInt() ?? 0;
  }

  Map<String, dynamic> _entryData({
    required AdventureEntryType type,
    required String title,
    required int deltaYen,
    required int balanceBeforeYen,
    required int balanceAfterYen,
    String? sourceId,
    String? note,
    DateTime? occurredAt,
  }) {
    return {
      'type': type.wireName,
      'sourceId': sourceId,
      'title': title,
      'deltaYen': deltaYen,
      'balanceBeforeYen': balanceBeforeYen,
      'balanceAfterYen': balanceAfterYen,
      'occurredAtUtc': occurredAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(occurredAt.toUtc()),
      'createdAtUtc': FieldValue.serverTimestamp(),
      if (note != null && note.isNotEmpty) 'note': note,
    };
  }

  Future<BalanceLedgerResult> adjustBalance({
    required int deltaYen,
    required AdventureEntryType type,
    required String title,
    String? sourceId,
    String? note,
    DateTime? occurredAt,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    if (deltaYen == 0) {
      final user = await _userRef(uid).get();
      final balance = _balanceFrom(user);
      return BalanceLedgerResult(
        applied: false,
        deltaYen: 0,
        balanceBeforeYen: balance,
        balanceAfterYen: balance,
      );
    }

    return _db.runTransaction((tx) async {
      final userRef = _userRef(uid);
      final userDoc = await tx.get(userRef);
      final before = _balanceFrom(userDoc);
      final after = before + deltaYen;
      final entryRef = _entriesCol(uid).doc();
      tx.set(userRef, {
        'totalEarned': after,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(
        entryRef,
        _entryData(
          type: type,
          title: title,
          deltaYen: deltaYen,
          balanceBeforeYen: before,
          balanceAfterYen: after,
          sourceId: sourceId,
          note: note,
          occurredAt: occurredAt,
        ),
      );
      return BalanceLedgerResult(
        applied: true,
        deltaYen: deltaYen,
        balanceBeforeYen: before,
        balanceAfterYen: after,
      );
    });
  }

  Future<BalanceLedgerResult> completeTask({
    required String taskId,
    required String title,
    required int rewardYen,
    required int predictedMinutes,
    required int? actualMinutes,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    return _db.runTransaction((tx) async {
      final userRef = _userRef(uid);
      final taskRef = userRef.collection('tasks').doc(taskId);
      final taskDoc = await tx.get(taskRef);
      final userDoc = await tx.get(userRef);
      final before = _balanceFrom(userDoc);
      final beforeCount = _cumulativeFrom(userDoc);
      if (taskDoc.data()?['isCompleted'] == true) {
        return BalanceLedgerResult(
          applied: false,
          deltaYen: 0,
          balanceBeforeYen: before,
          balanceAfterYen: before,
          cumulativeTaskCountBefore: beforeCount,
          cumulativeTaskCountAfter: beforeCount,
        );
      }

      final after = before + rewardYen;
      final afterCount = beforeCount + 1;
      final taskData = <String, dynamic>{
        'isCompleted': true,
        'completedAtUtc': FieldValue.serverTimestamp(),
        'completedRewardYen': rewardYen,
        'predictedMinutes': predictedMinutes,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (actualMinutes != null) taskData['actualMinutes'] = actualMinutes;

      tx.update(taskRef, taskData);
      // 累計タスク数も同一トランザクションで決定的にインクリメント（レベルのソース）。
      // 抽選（乱数）はトランザクション外で行う（リトライによる再ロールを避けるため）。
      tx.set(userRef, {
        'totalEarned': after,
        'cumulativeTaskCount': afterCount,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(
        _entriesCol(uid).doc(),
        _entryData(
          type: AdventureEntryType.taskCompleted,
          title: title,
          deltaYen: rewardYen,
          balanceBeforeYen: before,
          balanceAfterYen: after,
          sourceId: taskId,
        ),
      );
      return BalanceLedgerResult(
        applied: true,
        deltaYen: rewardYen,
        balanceBeforeYen: before,
        balanceAfterYen: after,
        cumulativeTaskCountBefore: beforeCount,
        cumulativeTaskCountAfter: afterCount,
      );
    });
  }

  Future<BalanceLedgerResult> revertTask({
    required String taskId,
    required String title,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    return _db.runTransaction((tx) async {
      final userRef = _userRef(uid);
      final taskRef = userRef.collection('tasks').doc(taskId);
      final taskDoc = await tx.get(taskRef);
      final userDoc = await tx.get(userRef);
      final before = _balanceFrom(userDoc);
      final beforeCount = _cumulativeFrom(userDoc);
      final taskData = taskDoc.data() ?? {};
      if (taskData['isCompleted'] != true) {
        return BalanceLedgerResult(
          applied: false,
          deltaYen: 0,
          balanceBeforeYen: before,
          balanceAfterYen: before,
          cumulativeTaskCountBefore: beforeCount,
          cumulativeTaskCountAfter: beforeCount,
        );
      }
      final reward = (taskData['completedRewardYen'] as num?)?.toInt();
      if (reward == null) {
        return BalanceLedgerResult(
          applied: false,
          deltaYen: 0,
          balanceBeforeYen: before,
          balanceAfterYen: before,
          missingAmount: true,
          cumulativeTaskCountBefore: beforeCount,
          cumulativeTaskCountAfter: beforeCount,
        );
      }

      final delta = -reward;
      final after = before + delta;
      // 累計タスク数を-1（0未満にしない）。発行済みチケットは取り消さない（仕様決定）。
      final afterCount = beforeCount > 0 ? beforeCount - 1 : 0;
      tx.update(taskRef, {
        'isCompleted': false,
        'completedAtUtc': FieldValue.delete(),
        'completedRewardYen': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(userRef, {
        'totalEarned': after,
        'cumulativeTaskCount': afterCount,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(
        _entriesCol(uid).doc(),
        _entryData(
          type: AdventureEntryType.taskReverted,
          title: title,
          deltaYen: delta,
          balanceBeforeYen: before,
          balanceAfterYen: after,
          sourceId: taskId,
        ),
      );
      return BalanceLedgerResult(
        applied: true,
        deltaYen: delta,
        balanceBeforeYen: before,
        balanceAfterYen: after,
        cumulativeTaskCountBefore: beforeCount,
        cumulativeTaskCountAfter: afterCount,
      );
    });
  }

  Future<BalanceLedgerResult> purchaseWish({
    required String itemId,
    required String title,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    return _db.runTransaction((tx) async {
      final userRef = _userRef(uid);
      final itemRef = userRef.collection('wishlist').doc(itemId);
      final itemDoc = await tx.get(itemRef);
      final userDoc = await tx.get(userRef);
      final before = _balanceFrom(userDoc);
      final itemData = itemDoc.data() ?? {};
      if (itemData['isPurchased'] == true) {
        return BalanceLedgerResult(
          applied: false,
          deltaYen: 0,
          balanceBeforeYen: before,
          balanceAfterYen: before,
        );
      }
      final price = (itemData['price'] as num?)?.toInt();
      if (price == null) {
        return BalanceLedgerResult(
          applied: false,
          deltaYen: 0,
          balanceBeforeYen: before,
          balanceAfterYen: before,
          missingAmount: true,
        );
      }
      if (before < price) {
        return BalanceLedgerResult(
          applied: false,
          deltaYen: 0,
          balanceBeforeYen: before,
          balanceAfterYen: before,
          insufficientFunds: true,
        );
      }

      final delta = -price;
      final after = before + delta;
      tx.update(itemRef, {
        'isPurchased': true,
        'purchasedAt': FieldValue.serverTimestamp(),
        'purchasedPriceYen': price,
      });
      tx.set(userRef, {
        'totalEarned': after,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(
        _entriesCol(uid).doc(),
        _entryData(
          type: AdventureEntryType.wishPurchased,
          title: title,
          deltaYen: delta,
          balanceBeforeYen: before,
          balanceAfterYen: after,
          sourceId: itemId,
        ),
      );
      return BalanceLedgerResult(
        applied: true,
        deltaYen: delta,
        balanceBeforeYen: before,
        balanceAfterYen: after,
      );
    });
  }

  Future<BalanceLedgerResult> unpurchaseWish({
    required String itemId,
    required String title,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    return _db.runTransaction((tx) async {
      final userRef = _userRef(uid);
      final itemRef = userRef.collection('wishlist').doc(itemId);
      final itemDoc = await tx.get(itemRef);
      final userDoc = await tx.get(userRef);
      final before = _balanceFrom(userDoc);
      final itemData = itemDoc.data() ?? {};
      if (itemData['isPurchased'] != true) {
        return BalanceLedgerResult(
          applied: false,
          deltaYen: 0,
          balanceBeforeYen: before,
          balanceAfterYen: before,
        );
      }
      final price =
          (itemData['purchasedPriceYen'] as num?)?.toInt() ??
          (itemData['price'] as num?)?.toInt();
      if (price == null) {
        return BalanceLedgerResult(
          applied: false,
          deltaYen: 0,
          balanceBeforeYen: before,
          balanceAfterYen: before,
          missingAmount: true,
        );
      }

      final after = before + price;
      tx.update(itemRef, {
        'isPurchased': false,
        'purchasedAt': FieldValue.delete(),
        'purchasedAtUtc': FieldValue.delete(),
        'purchasedPriceYen': FieldValue.delete(),
      });
      tx.set(userRef, {
        'totalEarned': after,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(
        _entriesCol(uid).doc(),
        _entryData(
          type: AdventureEntryType.wishUnpurchased,
          title: title,
          deltaYen: price,
          balanceBeforeYen: before,
          balanceAfterYen: after,
          sourceId: itemId,
          note: itemData['purchasedPriceYen'] == null ? '現在価格から推定' : null,
        ),
      );
      return BalanceLedgerResult(
        applied: true,
        deltaYen: price,
        balanceBeforeYen: before,
        balanceAfterYen: after,
      );
    });
  }

  Future<BalanceLedgerResult> saveHealthLogAndAdjust({
    required String dateKey,
    required Map<String, dynamic> healthLogData,
    required int deltaYen,
    String? entryTitle,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    return _db.runTransaction((tx) async {
      final userRef = _userRef(uid);
      final logRef = userRef.collection('healthLogs').doc(dateKey);
      final userDoc = await tx.get(userRef);
      final before = _balanceFrom(userDoc);
      tx.set(logRef, healthLogData, SetOptions(merge: true));
      if (deltaYen == 0) {
        return BalanceLedgerResult(
          applied: false,
          deltaYen: 0,
          balanceBeforeYen: before,
          balanceAfterYen: before,
        );
      }

      final after = before + deltaYen;
      tx.set(userRef, {
        'totalEarned': after,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(
        _entriesCol(uid).doc(),
        _entryData(
          type: AdventureEntryType.healthAdjusted,
          title: entryTitle == null || entryTitle.isEmpty
              ? '健康スコア'
              : entryTitle,
          deltaYen: deltaYen,
          balanceBeforeYen: before,
          balanceAfterYen: after,
          sourceId: dateKey,
        ),
      );
      return BalanceLedgerResult(
        applied: true,
        deltaYen: deltaYen,
        balanceBeforeYen: before,
        balanceAfterYen: after,
      );
    });
  }
}
