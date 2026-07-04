import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:task_manager/features/adventure_log/data/adventure_log_backfill.dart';
import 'package:task_manager/features/adventure_log/model/adventure_log_entry.dart';
import 'package:task_manager/features/wish_list/model/wish_item.dart';
import 'package:task_manager/models/calendar_task.dart';

class AdventureLogRepository {
  AdventureLogRepository({FirebaseFirestore? db, FirebaseAuth? auth})
    : _db = db ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  static const _backfillMarkerKey = 'adventureEntriesBackfillV1CompletedAtUtc';

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  Future<void>? _backfillFuture;

  Future<void> backfillLegacyEntriesIfNeeded() {
    final running = _backfillFuture;
    if (running != null) return running;

    final future = _backfillLegacyEntriesIfNeeded();
    _backfillFuture = future;
    return future.whenComplete(() {
      if (identical(_backfillFuture, future)) {
        _backfillFuture = null;
      }
    });
  }

  Future<void> _backfillLegacyEntriesIfNeeded() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final userRef = _db.collection('users').doc(uid);
    final userDoc = await userRef.get();
    final userData = userDoc.data() ?? {};
    if (userData[_backfillMarkerKey] != null) return;

    final currentBalanceYen = (userData['totalEarned'] as num?)?.toInt() ?? 0;

    final entriesSnap = await userRef.collection('adventure_entries').get();
    final existingEntries = entriesSnap.docs
        .map(AdventureLogEntry.fromFirestore)
        .toList();
    final existingEntryKeys = <String>{
      for (final entry in existingEntries)
        if (entry.sourceId != null)
          adventureEntryKey(entry.type, entry.sourceId!),
    };
    final anchors = existingEntries
        .where(
          (entry) =>
              entry.occurredAt != null &&
              entry.balanceBeforeYen != null &&
              entry.balanceAfterYen != null,
        )
        .map(
          (entry) => AdventureLedgerAnchor(
            occurredAt: entry.occurredAt!,
            balanceBeforeYen: entry.balanceBeforeYen!,
            balanceAfterYen: entry.balanceAfterYen!,
          ),
        )
        .toList();

    final tasksSnap = await userRef
        .collection('tasks')
        .where('isCompleted', isEqualTo: true)
        .get();
    final wishesSnap = await userRef
        .collection('wishlist')
        .where('isPurchased', isEqualTo: true)
        .get();

    final taskCandidates = <_TaskBackfillCandidate>[];
    for (final doc in tasksSnap.docs) {
      final task = CalendarTask.fromMap(doc.id, doc.data());
      final occurredAt = task.completedAt ?? task.updatedAt ?? task.end;
      if (occurredAt == null) continue;
      taskCandidates.add(
        _TaskBackfillCandidate(
          draft: AdventureBackfillDraft(
            type: AdventureEntryType.taskCompleted,
            sourceId: task.id,
            title: task.title,
            deltaYen: task.completedRewardYen ?? task.rewardYen,
            occurredAt: occurredAt,
            note: task.completedRewardYen == null ? '過去データから埋め戻し' : null,
          ),
          needsCompletedRewardPatch: task.completedRewardYen == null,
        ),
      );
    }

    final wishCandidates = <_WishBackfillCandidate>[];
    for (final doc in wishesSnap.docs) {
      final item = WishItem.fromFirestore(doc);
      final occurredAt = item.purchasedAt ?? item.createdAt;
      wishCandidates.add(
        _WishBackfillCandidate(
          draft: AdventureBackfillDraft(
            type: AdventureEntryType.wishPurchased,
            sourceId: item.id,
            title: item.name,
            deltaYen: -(item.purchasedPriceYen ?? item.price),
            occurredAt: occurredAt,
            note: (item.purchasedAt == null || item.purchasedPriceYen == null)
                ? '過去データから埋め戻し'
                : null,
          ),
          patchPurchasedAt: item.purchasedAt == null ? occurredAt : null,
          patchPurchasedPriceYen: item.purchasedPriceYen == null
              ? item.price
              : null,
        ),
      );
    }

    final pendingTaskDrafts = filterPendingAdventureBackfills(
      drafts: taskCandidates.map((candidate) => candidate.draft).toList(),
      existingEntryKeys: existingEntryKeys,
    );
    final pendingWishDrafts = filterPendingAdventureBackfills(
      drafts: wishCandidates.map((candidate) => candidate.draft).toList(),
      existingEntryKeys: existingEntryKeys,
    );
    final pendingKeys = <String>{
      ...pendingTaskDrafts.map((draft) => draft.entryKey),
      ...pendingWishDrafts.map((draft) => draft.entryKey),
    };
    final pendingDrafts = [...pendingTaskDrafts, ...pendingWishDrafts];

    if (pendingDrafts.isEmpty) {
      await userRef.set({
        _backfillMarkerKey: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final balancedDrafts = assignAdventureBackfillBalances(
      drafts: pendingDrafts,
      anchors: anchors,
      currentBalanceYen: currentBalanceYen,
    );
    final balancedByKey = <String, AdventureBackfillBalancedDraft>{
      for (final draft in balancedDrafts) draft.entryKey: draft,
    };

    final pendingWrites = <_PendingWrite>[];
    for (final candidate in taskCandidates) {
      final key = candidate.draft.entryKey;
      if (!pendingKeys.contains(key)) continue;
      final balanced = balancedByKey[key];
      if (balanced == null) continue;
      pendingWrites.add(
        _PendingWrite.entry(
          data: _entryData(
            type: balanced.type,
            title: balanced.title,
            deltaYen: balanced.deltaYen,
            balanceBeforeYen: balanced.balanceBeforeYen,
            balanceAfterYen: balanced.balanceAfterYen,
            sourceId: balanced.sourceId,
            note: balanced.note,
            occurredAt: balanced.occurredAt,
          ),
        ),
      );
      if (candidate.needsCompletedRewardPatch) {
        pendingWrites.add(
          _PendingWrite.update(
            ref: userRef.collection('tasks').doc(candidate.draft.sourceId),
            data: {
              'completedRewardYen': candidate.draft.deltaYen,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          ),
        );
      }
    }

    for (final candidate in wishCandidates) {
      final key = candidate.draft.entryKey;
      if (!pendingKeys.contains(key)) continue;
      final balanced = balancedByKey[key];
      if (balanced == null) continue;
      pendingWrites.add(
        _PendingWrite.entry(
          data: _entryData(
            type: balanced.type,
            title: balanced.title,
            deltaYen: balanced.deltaYen,
            balanceBeforeYen: balanced.balanceBeforeYen,
            balanceAfterYen: balanced.balanceAfterYen,
            sourceId: balanced.sourceId,
            note: balanced.note,
            occurredAt: balanced.occurredAt,
          ),
        ),
      );
      final wishPatch = <String, dynamic>{};
      if (candidate.patchPurchasedAt != null) {
        wishPatch['purchasedAt'] = Timestamp.fromDate(
          candidate.patchPurchasedAt!.toUtc(),
        );
      }
      if (candidate.patchPurchasedPriceYen != null) {
        wishPatch['purchasedPriceYen'] = candidate.patchPurchasedPriceYen;
      }
      if (wishPatch.isNotEmpty) {
        pendingWrites.add(
          _PendingWrite.update(
            ref: userRef.collection('wishlist').doc(candidate.draft.sourceId),
            data: wishPatch,
          ),
        );
      }
    }

    pendingWrites.add(
      _PendingWrite.set(
        ref: userRef,
        data: {_backfillMarkerKey: FieldValue.serverTimestamp()},
      ),
    );

    await _commitPendingWrites(userRef, pendingWrites);
  }

  /// backfill 済み（[_backfillMarkerKey] 済み）なら legacy tasks/wishlist の
  /// 購読は不要なため、adventure_entries のみ購読する（Firestore 読み取りコスト削減）。
  Stream<List<AdventureLogEntry>> watchEntries() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);

    final controller = StreamController<List<AdventureLogEntry>>();
    var ledgerEntries = const <AdventureLogEntry>[];
    var legacyTasks = const <AdventureLogEntry>[];
    var legacyWishes = const <AdventureLogEntry>[];
    final subscriptions = <StreamSubscription<dynamic>>[];
    var cancelled = false;

    void emit() {
      final merged = <AdventureLogEntry>[
        ...ledgerEntries,
        ...legacyTasks,
        ...legacyWishes,
      ]..sort((a, b) => b.sortAt.compareTo(a.sortAt));
      if (!controller.isClosed) controller.add(merged);
    }

    // 1本がエラーになったとき残り全 subscription をキャンセルしてから error を流す。
    void handleError(Object e, StackTrace st) {
      for (final sub in subscriptions) {
        sub.cancel();
      }
      if (!controller.isClosed) {
        controller.addError(e, st);
        controller.close();
      }
    }

    final userRef = _db.collection('users').doc(uid);
    subscriptions.add(
      userRef
          .collection('adventure_entries')
          .orderBy('occurredAtUtc', descending: true)
          .snapshots()
          .listen((snapshot) {
            ledgerEntries = snapshot.docs
                .map(AdventureLogEntry.fromFirestore)
                .toList();
            emit();
          }, onError: handleError),
    );

    userRef.get().then((doc) {
      if (cancelled) return;
      final backfilled = doc.data()?[_backfillMarkerKey] != null;
      if (backfilled) return;

      subscriptions.add(
        userRef
            .collection('tasks')
            .where('isCompleted', isEqualTo: true)
            .snapshots()
            .listen((snapshot) {
              legacyTasks = snapshot.docs
                  .map((doc) => CalendarTask.fromMap(doc.id, doc.data()))
                  .where(
                    (task) =>
                        task.completedAt != null &&
                        task.completedRewardYen == null,
                  )
                  .map(AdventureLogEntry.legacyTask)
                  .toList();
              emit();
            }, onError: handleError),
      );

      subscriptions.add(
        userRef
            .collection('wishlist')
            .where('isPurchased', isEqualTo: true)
            .snapshots()
            .listen((snapshot) {
              legacyWishes = snapshot.docs
                  .map(WishItem.fromFirestore)
                  .where((item) => item.purchasedAt == null)
                  .map(AdventureLogEntry.legacyWish)
                  .toList();
              emit();
            }, onError: handleError),
      );
    });

    controller.onCancel = () async {
      cancelled = true;
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    };
    return controller.stream;
  }

  Future<void> _commitPendingWrites(
    DocumentReference<Map<String, dynamic>> userRef,
    List<_PendingWrite> writes,
  ) async {
    var batch = _db.batch();
    var opCount = 0;

    Future<void> commitBatch() async {
      if (opCount == 0) return;
      await batch.commit();
      batch = _db.batch();
      opCount = 0;
    }

    for (final write in writes) {
      if (opCount >= 450) {
        await commitBatch();
      }
      switch (write.kind) {
        case _PendingWriteKind.entry:
          batch.set(userRef.collection('adventure_entries').doc(), write.data!);
          break;
        case _PendingWriteKind.update:
          batch.update(write.ref!, write.data!);
          break;
        case _PendingWriteKind.set:
          batch.set(write.ref!, write.data!, SetOptions(merge: true));
          break;
      }
      opCount++;
    }
    await commitBatch();
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
      'occurredAtUtc': Timestamp.fromDate(occurredAt!.toUtc()),
      'createdAtUtc': FieldValue.serverTimestamp(),
      if (note != null && note.isNotEmpty) 'note': note,
    };
  }
}

class _TaskBackfillCandidate {
  const _TaskBackfillCandidate({
    required this.draft,
    required this.needsCompletedRewardPatch,
  });

  final AdventureBackfillDraft draft;
  final bool needsCompletedRewardPatch;
}

class _WishBackfillCandidate {
  const _WishBackfillCandidate({
    required this.draft,
    this.patchPurchasedAt,
    this.patchPurchasedPriceYen,
  });

  final AdventureBackfillDraft draft;
  final DateTime? patchPurchasedAt;
  final int? patchPurchasedPriceYen;
}

enum _PendingWriteKind { entry, update, set }

class _PendingWrite {
  const _PendingWrite.entry({required this.data})
    : kind = _PendingWriteKind.entry,
      ref = null;

  const _PendingWrite.update({required this.ref, required this.data})
    : kind = _PendingWriteKind.update;

  const _PendingWrite.set({required this.ref, required this.data})
    : kind = _PendingWriteKind.set;

  final _PendingWriteKind kind;
  final DocumentReference<Map<String, dynamic>>? ref;
  final Map<String, dynamic>? data;
}
