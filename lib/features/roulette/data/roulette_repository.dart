import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:task_manager/features/roulette/model/reward_config.dart';
import 'package:task_manager/features/roulette/model/reward_ticket.dart';

/// ご褒美チケット在庫（`reward_tickets`）の永続化と、累計タスク数のバックフィルを担う。
///
/// 抽選（乱数）はトランザクションの外（[viewmodel]）で行い、ここはその結果を冪等に保存する。
class RouletteRepository {
  RouletteRepository({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _ticketsCol(String uid) =>
      _userRef(uid).collection('reward_tickets');

  /// 完了IDから決定的なチケットドキュメントIDを作る（リトライ／再送による二重発行を防ぐ）。
  static String ticketIdForCompletion(String completionId) =>
      '${completionId}_complete';

  /// 当たり（中／大）でチケットを在庫に発行する。同一完了からの再発行は冪等（上書き・二重発行しない）。
  Future<void> issueTicket({
    required String completionId,
    required RouletteCategory tier,
    required String rewardName,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    final ref = _ticketsCol(uid).doc(ticketIdForCompletion(completionId));
    await _db.runTransaction((tx) async {
      final existing = await tx.get(ref);
      if (existing.exists) return; // 既発行 → 何もしない（冪等）
      tx.set(
        ref,
        RewardTicket(
          id: ref.id,
          tier: tier,
          rewardName: rewardName,
          wonAt: DateTime.now(),
        ).toFirestore(),
      );
    });
  }

  /// 未使用チケットの在庫ストリーム（新しい順）。
  /// where(used) + orderBy(wonAt) の複合インデックスを避けるためソートはクライアント側で行う。
  Stream<List<RewardTicket>> watchUnusedTickets() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    return _ticketsCol(uid).where('used', isEqualTo: false).snapshots().map(
          (snap) => snap.docs.map(RewardTicket.fromFirestore).toList()
            ..sort((a, b) => b.wonAt.compareTo(a.wonAt)),
        );
  }

  /// チケットを消費する（使用済みに移動）。すでに使用済みなら false（二重消費防止）。
  Future<bool> consumeTicket(String ticketId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    final ref = _ticketsCol(uid).doc(ticketId);
    return _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) return false;
      if (doc.data()?['used'] == true) return false;
      tx.update(ref, {
        'used': true,
        'usedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  /// 消費を取り消して在庫に戻す（UI の Undo 用）。
  Future<void> restoreTicket(String ticketId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    await _ticketsCol(uid).doc(ticketId).update({
      'used': false,
      'usedAt': FieldValue.delete(),
    });
  }

  /// 累計タスク数を既存の完了タスクから一度だけバックフィルする。
  /// `cumulativeTaskCountBackfilledAt` をガードに、二重実行しても増えない。
  /// Firestore はトランザクション内でクエリできないため、集計は外で行い、書き込みのみ tx で保護する。
  Future<void> ensureCumulativeTaskCountBackfilled() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final userRef = _userRef(uid);
    final userDoc = await userRef.get();
    if (userDoc.data()?['cumulativeTaskCountBackfilledAt'] != null) return;

    final agg = await userRef
        .collection('tasks')
        .where('isCompleted', isEqualTo: true)
        .count()
        .get();
    final completedCount = agg.count ?? 0;

    await _db.runTransaction((tx) async {
      final fresh = await tx.get(userRef);
      if (fresh.data()?['cumulativeTaskCountBackfilledAt'] != null) return;
      final existing =
          (fresh.data()?['cumulativeTaskCount'] as num?)?.toInt() ?? 0;
      tx.set(
        userRef,
        {
          'cumulativeTaskCount':
              existing > completedCount ? existing : completedCount,
          'cumulativeTaskCountBackfilledAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }
}
