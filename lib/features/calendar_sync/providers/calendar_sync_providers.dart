// 設計メモ:
// Visibility / Download / Quadrant は別ドキュメント（settings/calendarVisibility 等）を
// 各1回 get する設計。常時表示のホーム画面が依存するため autoDispose は付けない。
// StreamProvider 化は setVisible 等の楽観的更新（state 先行更新）との整合検証が必要なため見送り。

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/core/providers/firebase_providers.dart';
import 'package:task_manager/features/calendar_sync/data/calendar_task_sync_repository.dart';
import 'package:task_manager/features/calendar_sync/data/google_calendar_repository.dart';
import 'package:task_manager/features/calendar_sync/model/google_account_info.dart';
import 'package:task_manager/features/calendar_sync/viewmodel/calendar_sync_viewmodel.dart';
import 'package:task_manager/models/calendar_task.dart';

final googleCalendarRepositoryProvider = Provider<GoogleCalendarRepository>(
  (_) => GoogleCalendarRepository(),
);

final calendarTaskSyncRepositoryProvider = Provider<CalendarTaskSyncRepository>(
  (_) => CalendarTaskSyncRepository(),
);

final calendarSyncViewModelProvider =
    NotifierProvider<CalendarSyncViewModel, CalendarSyncState>(
  CalendarSyncViewModel.new,
);

/// Googleカレンダーごとの色マップ。カレンダー取得後に populate される。
/// 再起動後は空。次回 "取得" 時に再ロードされるまで Google イベントは
/// フォールバック色で表示される（MVP仕様：Firestore永続化は別途）。
final calendarColorsProvider = Provider<Map<String, Color>>((ref) {
  final calendars = ref.watch(
    calendarSyncViewModelProvider.select((vm) => vm.calendars),
  );
  final map = <String, Color>{};
  for (final c in calendars) {
    final hex = c.colorHex;
    if (hex == null) continue;
    final parsed = _parseHexColor(hex);
    if (parsed != null) map[c.id] = parsed;
  }
  return map;
});

/// 可視（チェックON）な Google カレンダーID集合を、Google アカウントIDごとに管理。
/// Firestore パス: `users/{uid}/settings/calendarVisibility`
/// フィールド:
///   visible: { `accountId`: { `calendarId`: bool } }
class CalendarVisibilityNotifier
    extends AsyncNotifier<Map<String, Set<String>>> {
  DocumentReference<Map<String, dynamic>>? _docRef() {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return null;
    return ref
        .read(firebaseFirestoreProvider)
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('calendarVisibility');
  }

  @override
  FutureOr<Map<String, Set<String>>> build() async {
    final ref = _docRef();
    if (ref == null) return {};
    try {
      final doc = await ref.get();
      if (!doc.exists) return {};
      final data = doc.data() ?? {};
      final visible = data['visible'] as Map<String, dynamic>? ?? {};
      final result = <String, Set<String>>{};
      visible.forEach((accountId, v) {
        final inner = (v as Map<String, dynamic>?) ?? const {};
        final ids = <String>{};
        inner.forEach((calId, flag) {
          if (flag == true) ids.add(calId);
        });
        result[accountId] = ids;
      });
      return result;
    } catch (e) {
      debugPrint('CalendarVisibilityNotifier.build error: $e');
      return {};
    }
  }

  /// 指定アカウント×カレンダーの可視を設定。Firestore も更新。
  /// 書き込みに失敗した場合は state を更新前の値に戻し `false` を返す。
  Future<bool> setVisible({
    required String accountId,
    required String calendarId,
    required bool visible,
  }) async {
    final previous = state.asData?.value ?? const <String, Set<String>>{};
    final currentForAccount = previous[accountId] ?? const <String>{};
    final nextForAccount = <String>{...currentForAccount};
    if (visible) {
      nextForAccount.add(calendarId);
    } else {
      nextForAccount.remove(calendarId);
    }
    state = AsyncValue.data({
      ...previous,
      accountId: nextForAccount,
    });
    final ref = _docRef();
    if (ref == null) return true;
    try {
      await ref.set({
        'visible': {
          accountId: {calendarId: visible},
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('CalendarVisibilityNotifier.setVisible error: $e');
      state = AsyncValue.data(previous);
      return false;
    }
  }

  bool isVisible(String accountId, String calendarId) {
    return state.asData?.value[accountId]?.contains(calendarId) ?? false;
  }
}

final calendarVisibilityProvider = AsyncNotifierProvider<
    CalendarVisibilityNotifier,
    Map<String, Set<String>>>(CalendarVisibilityNotifier.new);

/// 軽量な同期ビュー（UI での頻繁なチェック向け）。ロード前は空 Map を返す。
final calendarVisibilityMapProvider = Provider<Map<String, Set<String>>>((ref) {
  final async = ref.watch(calendarVisibilityProvider);
  return async.asData?.value ?? const <String, Set<String>>{};
});

/// ダウンロード（タスク化）対象の Google カレンダーID集合を、Google アカウントIDごとに管理。
/// Firestore パス: `users/{uid}/settings/calendarDownload`
/// フィールド:
///   downloaded: { `accountId`: { `calendarId`: bool } }
class CalendarDownloadNotifier
    extends AsyncNotifier<Map<String, Set<String>>> {
  DocumentReference<Map<String, dynamic>>? _docRef() {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return null;
    return ref
        .read(firebaseFirestoreProvider)
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('calendarDownload');
  }

  @override
  FutureOr<Map<String, Set<String>>> build() async {
    final ref = _docRef();
    if (ref == null) return {};
    try {
      final doc = await ref.get();
      if (!doc.exists) return {};
      final data = doc.data() ?? {};
      final downloaded = data['downloaded'] as Map<String, dynamic>? ?? {};
      final result = <String, Set<String>>{};
      downloaded.forEach((accountId, v) {
        final inner = (v as Map<String, dynamic>?) ?? const {};
        final ids = <String>{};
        inner.forEach((calId, flag) {
          if (flag == true) ids.add(calId);
        });
        result[accountId] = ids;
      });
      return result;
    } catch (e) {
      debugPrint('CalendarDownloadNotifier.build error: $e');
      return {};
    }
  }

  /// 指定アカウント×カレンダーのDLフラグを設定。Firestore も更新。
  /// 書き込みに失敗した場合は state を更新前の値に戻し `false` を返す。
  Future<bool> setDownloaded({
    required String accountId,
    required String calendarId,
    required bool downloaded,
  }) async {
    final previous = state.asData?.value ?? const <String, Set<String>>{};
    final currentForAccount = previous[accountId] ?? const <String>{};
    final nextForAccount = <String>{...currentForAccount};
    if (downloaded) {
      nextForAccount.add(calendarId);
    } else {
      nextForAccount.remove(calendarId);
    }
    state = AsyncValue.data({
      ...previous,
      accountId: nextForAccount,
    });
    final ref = _docRef();
    if (ref == null) return true;
    try {
      await ref.set({
        'downloaded': {
          accountId: {calendarId: downloaded},
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('CalendarDownloadNotifier.setDownloaded error: $e');
      state = AsyncValue.data(previous);
      return false;
    }
  }

  bool isDownloaded(String accountId, String calendarId) {
    return state.asData?.value[accountId]?.contains(calendarId) ?? false;
  }
}

final calendarDownloadProvider = AsyncNotifierProvider<
    CalendarDownloadNotifier,
    Map<String, Set<String>>>(CalendarDownloadNotifier.new);

/// 軽量な同期ビュー。ロード前は空 Map を返す。
final calendarDownloadMapProvider = Provider<Map<String, Set<String>>>((ref) {
  final async = ref.watch(calendarDownloadProvider);
  return async.asData?.value ?? const <String, Set<String>>{};
});

/// カレンダーごとのデフォルト象限（1〜4）を管理。
/// Firestore パス: `users/{uid}/settings/calendarQuadrant`
/// フィールド:
///   quadrants: { `accountId`: { `calendarId`: int } }
class CalendarQuadrantNotifier
    extends AsyncNotifier<Map<String, Map<String, int>>> {
  DocumentReference<Map<String, dynamic>>? _docRef() {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return null;
    return ref
        .read(firebaseFirestoreProvider)
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('calendarQuadrant');
  }

  @override
  FutureOr<Map<String, Map<String, int>>> build() async {
    final ref = _docRef();
    if (ref == null) return {};
    try {
      final doc = await ref.get();
      if (!doc.exists) return {};
      final data = doc.data() ?? {};
      final quadrants = data['quadrants'] as Map<String, dynamic>? ?? {};
      final result = <String, Map<String, int>>{};
      quadrants.forEach((accountId, v) {
        final inner = (v as Map<String, dynamic>?) ?? const {};
        final calMap = <String, int>{};
        inner.forEach((calId, value) {
          if (value is int) calMap[calId] = value;
        });
        result[accountId] = calMap;
      });
      return result;
    } catch (e) {
      debugPrint('CalendarQuadrantNotifier.build error: $e');
      return {};
    }
  }

  /// 書き込みに失敗した場合は state を更新前の値に戻し `false` を返す。
  Future<bool> setQuadrant({
    required String accountId,
    required String calendarId,
    required int quadrantNumber,
  }) async {
    final previous = state.asData?.value ?? const <String, Map<String, int>>{};
    final currentForAccount =
        previous[accountId] ?? const <String, int>{};
    state = AsyncValue.data({
      ...previous,
      accountId: {...currentForAccount, calendarId: quadrantNumber},
    });
    final ref = _docRef();
    if (ref == null) return true;
    try {
      await ref.set({
        'quadrants': {
          accountId: {calendarId: quadrantNumber},
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('CalendarQuadrantNotifier.setQuadrant error: $e');
      state = AsyncValue.data(previous);
      return false;
    }
  }

  int getQuadrant(String accountId, String calendarId) {
    return state.asData?.value[accountId]?[calendarId] ?? 1;
  }
}

final calendarQuadrantProvider = AsyncNotifierProvider<
    CalendarQuadrantNotifier,
    Map<String, Map<String, int>>>(CalendarQuadrantNotifier.new);

final calendarQuadrantMapProvider =
    Provider<Map<String, Map<String, int>>>((ref) {
  final async = ref.watch(calendarQuadrantProvider);
  return async.asData?.value ?? const <String, Map<String, int>>{};
});

/// 現在 Google Calendar 連携でアクティブなアカウント。
/// ピッカー選択後に設定、セッション中はその値を使って取得する。
/// MVP では 1アカウント同時動作、切替時はこの値が更新される。
class CurrentGoogleAccountNotifier extends Notifier<GoogleAccountInfo?> {
  @override
  GoogleAccountInfo? build() => null;
  void set(GoogleAccountInfo? account) => state = account;
  void clear() => state = null;
}

final currentGoogleAccountProvider =
    NotifierProvider<CurrentGoogleAccountNotifier, GoogleAccountInfo?>(
  CurrentGoogleAccountNotifier.new,
);

/// タスクのLongPressDraggableがドラッグ中かどうか。
/// 日ビューで画面端ホバー時の自動ページングに使用。
class IsDraggingTaskNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void setDragging(bool v) => state = v;
}

final isDraggingTaskProvider =
    NotifierProvider<IsDraggingTaskNotifier, bool>(
  IsDraggingTaskNotifier.new,
);

Color? _parseHexColor(String hex) {
  var clean = hex.replaceAll('#', '').trim();
  if (clean.length == 6) clean = 'FF$clean';
  if (clean.length != 8) return null;
  final value = int.tryParse(clean, radix: 16);
  return value == null ? null : Color(value);
}

typedef _CalendarWeekKey = ({
  String accountId,
  String calendarId,
  DateTime weekStart,
});

/// カレンダー単位・週単位の生イベント取得（可視設定には依存しない）。
/// 一定時間キャッシュすることで、画面遷移や可視設定トグルのたびに
/// 同じ週を再フェッチしないようにする。
final _calendarWeekEventsProvider = FutureProvider.autoDispose
    .family<List<CalendarTask>, _CalendarWeekKey>((ref, key) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 15), link.close);
  ref.onDispose(timer.cancel);

  final repo = ref.read(googleCalendarRepositoryProvider);
  return repo.fetchWeekEvents(
    calendarId: key.calendarId,
    weekStartLocal: key.weekStart,
    accountId: key.accountId,
  );
});

/// 指定週のリモート（Google Calendar）イベントを取得するプロバイダ。
/// 仕様に従い Firestore には保存しない。currentGoogleAccount と可視カレンダー設定に連動。
/// 実際のフェッチ（ネットワークI/O）は [_calendarWeekEventsProvider] でキャッシュされるため、
/// 可視設定のトグルはここでの再フィルタのみで完結し、表示中の他カレンダーの再フェッチは発生しない。
final remoteWeekEventsProvider = FutureProvider.autoDispose
    .family<List<CalendarTask>, DateTime>((ref, weekStart) async {
  final account = ref.watch(currentGoogleAccountProvider);
  if (account == null) return const [];
  final visibilityMap = ref.watch(calendarVisibilityMapProvider);
  final visibleCalIds = visibilityMap[account.id] ?? const <String>{};
  if (visibleCalIds.isEmpty) return const [];

  final collected = <CalendarTask>[];
  for (final calId in visibleCalIds) {
    try {
      final events = await ref.watch(
        _calendarWeekEventsProvider((
          accountId: account.id,
          calendarId: calId,
          weekStart: weekStart,
        )).future,
      );
      collected.addAll(events);
    } catch (e) {
      debugPrint('remoteWeekEventsProvider: fetch failed for $calId: $e');
      // 一部カレンダーの失敗は他をブロックしない
    }
  }
  return collected;
});

/// 指定週（月曜 0:00 ローカル）の Firestore タスクをリアルタイム監視する。
/// 取り込み後に自動更新される。
final weekTasksProvider =
    StreamProvider.autoDispose.family<List<CalendarTask>, DateTime>(
        (ref, weekStart) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);

  final weekEnd = weekStart.add(const Duration(days: 7));

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('tasks')
      .where('startAtUtc',
          isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart.toUtc()))
      .where('startAtUtc',
          isLessThan: Timestamp.fromDate(weekEnd.toUtc()))
      .orderBy('startAtUtc')
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => CalendarTask.fromMap(doc.id, doc.data()))
          .toList());
});
