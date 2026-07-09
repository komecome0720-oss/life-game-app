import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:task_manager/features/adventure_log/model/adventure_log_entry.dart';
import 'package:task_manager/features/health/model/health_log.dart';

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

  CollectionReference<Map<String, dynamic>> _dailyEarningsCol(String uid) =>
      _userRef(uid).collection('daily_earnings');

  String? _dailyEarningsFieldFor(AdventureEntryType type) {
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

  String _localDateKey(DateTime date) {
    final local = date.toLocal();
    String pad2(int v) => v.toString().padLeft(2, '0');
    return '${local.year.toString().padLeft(4, '0')}-${pad2(local.month)}-${pad2(local.day)}';
  }

  /// 'yyyy-MM-dd' → その日のローカル正午 DateTime。
  /// 日次収支グラフの帰属日など、範囲の境界に依存しない安全な代表時刻として使う。
  DateTime _dateFromKey(String dateKey) {
    final parts = dateKey.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    return DateTime(year, month, day, 12);
  }

  /// wish系タイプは何もしない。日次集計コレクション `daily_earnings` へ
  /// `FieldValue.increment` で加算する（順序非依存。クランプは表示側で行う）。
  void _applyDailyEarning(
    Transaction tx,
    String uid,
    AdventureEntryType type,
    int deltaYen,
    DateTime? occurredAt,
  ) {
    final field = _dailyEarningsFieldFor(type);
    if (field == null) return;
    final dateKey = _localDateKey(occurredAt ?? DateTime.now());
    final dailyRef = _dailyEarningsCol(uid).doc(dateKey);
    tx.set(dailyRef, {
      field: FieldValue.increment(deltaYen),
      'updatedAtUtc': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
      _applyDailyEarning(tx, uid, type, deltaYen, occurredAt);
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
      _applyDailyEarning(
        tx,
        uid,
        AdventureEntryType.taskCompleted,
        rewardYen,
        null,
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
      _applyDailyEarning(tx, uid, AdventureEntryType.taskReverted, delta, null);
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

  /// ポモドーロ作業フェーズ・通常タイマー計測の消化秒を `daily_earnings` の
  /// `workSeconds` へ加算する（ホームの「今日の作業時間」表示用）。
  /// [seconds] が0以下なら no-op。加算先の dateKey は [when]（既定 now）の
  /// ローカル日付（taskYen 等と同じ流儀）。
  Future<void> addWorkSeconds(int seconds, {DateTime? when}) async {
    if (seconds <= 0) return;
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    final dateKey = _localDateKey(when ?? DateTime.now());
    final ref = _dailyEarningsCol(uid).doc(dateKey);
    await ref.set({
      'workSeconds': FieldValue.increment(seconds),
      'updatedAtUtc': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<BalanceLedgerResult> saveHealthLogAndAdjust({
    required String dateKey,
    required Map<String, dynamic> healthLogData,
    required int deltaYen,
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
          title: '健康スコア',
          deltaYen: deltaYen,
          balanceBeforeYen: before,
          balanceAfterYen: after,
          sourceId: dateKey,
        ),
      );
      _applyDailyEarning(
        tx,
        uid,
        AdventureEntryType.healthAdjusted,
        deltaYen,
        null,
      );
      return BalanceLedgerResult(
        applied: true,
        deltaYen: deltaYen,
        balanceBeforeYen: before,
        balanceAfterYen: after,
      );
    });
  }

  /// 指定日の健康ログを確定させる（Design A：深夜/次回起動確定）。
  /// 冪等（`isFinalized` なら即return）。既に残高へ反映済みの額（[HealthLog.balanceAppliedYen]）
  /// を差し引き、超過分だけ `totalEarned` へ加算する（移行時の二重加算防止＝C-1）。
  /// ログが存在しない日は未達（0円）として何もしない。
  Future<void> finalizeHealthLog({required String dateKey}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    await _db.runTransaction((tx) async {
      final userRef = _userRef(uid);
      final logRef = userRef.collection('healthLogs').doc(dateKey);
      // --- 全read先に ---
      final logDoc = await tx.get(logRef);
      if (!logDoc.exists) return; // ログ無し日は何もしない（未達扱い＝0）
      final log = HealthLog.fromFirestore(logDoc);
      if (log.isFinalized) return; // 冪等：二重確定・二重加算を防ぐ
      final userDoc = await tx.get(userRef);
      final before = _balanceFrom(userDoc);
      final earned = log.provisionalEarnedYen; // 新式で既にゲート済み(0 or round(cap×p))
      // 既に残高へ反映済みの額(balanceAppliedYen)を差し引き、超過分だけ加算。
      final delta = earned - log.balanceAppliedYen;
      final add = delta > 0 ? delta : 0;
      // --- write ---
      tx.set(logRef, {
        'isFinalized': true,
        'finalizedEarnedYen': earned,
        'balanceAppliedYen': log.balanceAppliedYen + add,
        'finalizedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (add > 0) {
        final after = before + add;
        tx.set(userRef, {
          'totalEarned': after,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        tx.set(
          _entriesCol(uid).doc(),
          _entryData(
            type: AdventureEntryType.healthAdjusted,
            title: '健康スコア',
            deltaYen: add,
            balanceBeforeYen: before,
            balanceAfterYen: after,
            sourceId: dateKey,
            occurredAt: _dateFromKey(dateKey), // 帰属日をログの日付に
          ),
        );
        _applyDailyEarning(
          tx,
          uid,
          AdventureEntryType.healthAdjusted,
          add,
          _dateFromKey(dateKey),
        );
      }
    });
  }

  /// 旧モデル（日中に残高反映）→新モデル（Design A：深夜確定）移行の一回限りスイープ。
  /// `healthMigratedV2` フラグで冪等。未確定ログに「旧モデルで既に反映済みの額
  /// （＝旧 provisional）」を `balanceAppliedYen` として封印し、[finalizeHealthLog] の
  /// 差分加算で二重加算されないようにする（C-1）。
  Future<void> migrateHealthBalanceV2() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final userRef = _userRef(uid);
    final userDoc = await userRef.get();
    if ((userDoc.data()?['healthMigratedV2'] as bool?) ?? false) return; // 冪等
    final snaps = await userRef
        .collection('healthLogs')
        .where('isFinalized', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (final d in snaps.docs) {
      final log = HealthLog.fromFirestore(d);
      batch.set(d.reference, {
        'balanceAppliedYen': log.provisionalEarnedYen,
      }, SetOptions(merge: true));
    }
    batch.set(userRef, {
      'healthMigratedV2': true,
    }, SetOptions(merge: true));
    await batch.commit();
  }
}
