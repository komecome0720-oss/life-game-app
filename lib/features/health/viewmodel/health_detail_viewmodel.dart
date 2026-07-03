import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';
import 'package:task_manager/features/economy/data/economy_repository.dart';
import 'package:task_manager/features/economy/providers/economy_providers.dart';
import 'package:task_manager/features/health/model/health_category.dart';
import 'package:task_manager/features/health/model/health_log.dart';
import 'package:task_manager/features/health/model/health_rollover.dart';
import 'package:task_manager/features/health/model/health_scoring.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';

class HealthDetailState {
  const HealthDetailState({
    required this.log,
    this.isLoading = false,
    this.isEditableNow = true,
    this.errorMessage,
    this.lastSavedProvisionalYen = 0,
    List<HealthLog> historyLogs = const [],
    bool isHistoryLoading = false,
    String? historyErrorMessage,
  }) : _historyLogs = historyLogs,
       _isHistoryLoading = isHistoryLoading,
       _historyErrorMessage = historyErrorMessage;

  final HealthLog log;
  final bool isLoading;

  /// 当日判定（日付境界を越えたら false）
  final bool isEditableNow;

  final String? errorMessage;

  /// 直近の Firestore 書き込み時点の provisional。totalEarned 差分計算に使用。
  final int lastSavedProvisionalYen;

  // Hot reload直後の古いStateインスタンスでも安全に読めるよう、
  // 追加フィールドはnullableで保持しつつ公開getterで既定値に寄せる。
  final List<HealthLog>? _historyLogs;
  final bool? _isHistoryLoading;
  final String? _historyErrorMessage;

  List<HealthLog> get historyLogs => _historyLogs ?? const [];
  bool get isHistoryLoading => _isHistoryLoading ?? false;
  String? get historyErrorMessage => _historyErrorMessage;

  HealthDetailState copyWith({
    HealthLog? log,
    bool? isLoading,
    bool? isEditableNow,
    String? errorMessage,
    int? lastSavedProvisionalYen,
    List<HealthLog>? historyLogs,
    bool? isHistoryLoading,
    Object? historyErrorMessage = _unset,
  }) {
    return HealthDetailState(
      log: log ?? this.log,
      isLoading: isLoading ?? this.isLoading,
      isEditableNow: isEditableNow ?? this.isEditableNow,
      errorMessage: errorMessage,
      lastSavedProvisionalYen:
          lastSavedProvisionalYen ?? this.lastSavedProvisionalYen,
      historyLogs: historyLogs ?? this.historyLogs,
      isHistoryLoading: isHistoryLoading ?? this.isHistoryLoading,
      historyErrorMessage: identical(historyErrorMessage, _unset)
          ? this.historyErrorMessage
          : historyErrorMessage as String?,
    );
  }

  static const Object _unset = Object();
}

class HealthDetailViewModel extends Notifier<HealthDetailState> {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  String? get _uid => _auth.currentUser?.uid;

  Timer? _midnightTimer;
  final Set<Future<void>> _activeSaves = {};
  bool _isRefreshingForToday = false;
  int _stateGeneration = 0;

  /// build 時にキャプチャした repo。onDispose 内では ref.read が使えないため、
  /// settle をどの経路からでも同じ参照で呼べるよう保持する。
  late EconomyRepository _economyRepo;

  @override
  HealthDetailState build() {
    _economyRepo = ref.read(economyRepositoryProvider);
    ref.onDispose(() {
      _midnightTimer?.cancel();
      // PopScope／ライフサイクル監視を経由せず破棄された場合の保険。
      // await できないため fire-and-forget（破棄済み state の参照は settle 内で握り潰す）。
      unawaited(settlePendingLedger());
    });
    // ログイン状態（uid）の変化を購読し、サインイン直後に再ビルド→再ロードする。
    final uid = ref.watch(
      authStateProvider.select((async) => async.asData?.value?.uid),
    );
    _scheduleMidnightRollover();
    // 目標値や時間単価が変わったら、再計算して保存する。
    ref.listen<UserSettingsState>(userSettingsProvider, (prev, next) {
      if (prev == null) return;
      if (_goalsAffectScore(prev.settings, next.settings)) {
        _onGoalsChanged();
      }
    });
    final emptyLog = HealthLog(dateKey: HealthRollover.dateKey(DateTime.now()));
    if (uid == null) {
      return HealthDetailState(log: emptyLog, isLoading: false);
    }
    // 初期ロードは非同期。現時点は今日の空ログで isLoading=true。
    Future.microtask(() => _load(uid));
    return HealthDetailState(
      log: emptyLog,
      isLoading: true,
      isHistoryLoading: true,
    );
  }

  bool _goalsAffectScore(UserSettings a, UserSettings b) {
    return a.mealGoalGrams != b.mealGoalGrams ||
        a.exerciseGoalMinutes != b.exerciseGoalMinutes ||
        a.sleepGoalHours != b.sleepGoalHours ||
        a.sleepGoalMinutesExtra != b.sleepGoalMinutesExtra ||
        a.meditationGoalMinutes != b.meditationGoalMinutes ||
        a.hourlyRate != b.hourlyRate;
  }

  Future<void> _onGoalsChanged() async {
    if (_isRefreshingForToday ||
        state.isLoading ||
        !state.isEditableNow ||
        state.log.isFinalized) {
      return;
    }
    final uid = _uid;
    if (uid == null) return;
    final saveDateKey = state.log.dateKey;
    final saveGeneration = _stateGeneration;
    final settings = ref.read(userSettingsProvider).settings;
    final recomputed = _recompute(state.log, settings);
    if (recomputed.totalScore == state.log.totalScore &&
        recomputed.provisionalEarnedYen == state.log.provisionalEarnedYen) {
      return;
    }
    // 台帳・残高は退出時 settlePendingLedger() でまとめて確定する。
    // ここでは healthLog の値だけを保存し、baseline は据え置く。
    state = state.copyWith(log: recomputed);
    try {
      await _trackActiveSave(
        _economyRepo.saveHealthLogAndAdjust(
          dateKey: recomputed.dateKey,
          healthLogData: recomputed.toFirestore(),
          deltaYen: 0,
        ),
      );
    } catch (e) {
      if (_shouldApplySaveResult(uid, saveDateKey, saveGeneration)) {
        state = state.copyWith(errorMessage: '保存に失敗しました: $e');
      }
    }
  }

  void _scheduleMidnightRollover() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final delay = nextMidnight.difference(now) + const Duration(seconds: 1);
    _midnightTimer = Timer(delay, () async {
      await refreshForToday();
      _scheduleMidnightRollover();
    });
  }

  Future<void> _load(String uid) async {
    final loadGeneration = ++_stateGeneration;
    final todayKey = HealthRollover.dateKey(DateTime.now());
    try {
      final col = _db.collection('users').doc(uid).collection('healthLogs');
      final pastResult = await _fetchPastLogs(col, todayKey);

      final doc = await col.doc(todayKey).get();
      // ロード中にユーザーが切り替わった場合は破棄
      if (_uid != uid || loadGeneration != _stateGeneration) return;
      final loadedLog = doc.exists
          ? HealthLog.fromFirestore(doc)
          : HealthLog(dateKey: todayKey);
      final settings = ref.read(userSettingsProvider).settings;
      final log = await _syncTodayLogIfNeeded(
        uid: uid,
        log: loadedLog,
        settings: settings,
      );
      if (_uid != uid || loadGeneration != _stateGeneration) return;

      state = HealthDetailState(
        log: log,
        isLoading: false,
        isEditableNow: true,
        errorMessage: pastResult.error,
        // baseline は totalEarned に反映済みの額＝ディスクから読んだ値（sync前）。
        // sync で値が変わっても totalEarned は動いていないため recomputed 値は使わない。
        lastSavedProvisionalYen: loadedLog.provisionalEarnedYen,
        historyLogs: pastResult.logs.take(14).toList(growable: false),
        isHistoryLoading: false,
        historyErrorMessage: null,
      );
    } catch (e) {
      if (_uid != uid || loadGeneration != _stateGeneration) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: '読み込みに失敗しました: $e',
        isHistoryLoading: false,
        historyLogs: const [],
      );
    }
  }

  /// 過去ログを最大20件フェッチし、未確定ログをWriteBatchで一括確定させる。
  /// FieldPath.documentId の降順 orderBy は __name__ DESC の手動インデックスが必要。
  /// dateKey は常にドキュメントIDと同値で、自動の単一フィールドインデックスで足りる。
  Future<({List<HealthLog> logs, String? error})> _fetchPastLogs(
    CollectionReference<Map<String, dynamic>> col,
    String todayKey,
  ) async {
    try {
      final snaps = await col
          .where('dateKey', isLessThan: todayKey)
          .orderBy('dateKey', descending: true)
          .limit(20)
          .get();

      final batch = _db.batch();
      var hasBatchWrites = false;

      final logs = snaps.docs.map((doc) {
        final log = HealthLog.fromFirestore(doc);
        if (log.isFinalized) return log;
        final finalized = log.copyWith(
          isFinalized: true,
          finalizedEarnedYen: log.provisionalEarnedYen,
          finalizedAt: DateTime.now(),
        );
        batch.set(doc.reference, finalized.toFirestore(), SetOptions(merge: true));
        hasBatchWrites = true;
        return finalized;
      }).toList(growable: false);

      if (hasBatchWrites) await batch.commit();
      return (logs: logs, error: null);
    } catch (e) {
      return (logs: <HealthLog>[], error: '過去の健康ログ確定に失敗しました: $e');
    }
  }

  Future<void> _finalizeSavedLogForDate({
    required CollectionReference<Map<String, dynamic>> col,
    required String dateKey,
  }) async {
    final doc = await col.doc(dateKey).get();
    final log = doc.exists
        ? HealthLog.fromFirestore(doc)
        : HealthLog(dateKey: dateKey);
    if (log.isFinalized) return;
    final finalized = log.copyWith(
      isFinalized: true,
      finalizedEarnedYen: log.provisionalEarnedYen,
      finalizedAt: DateTime.now(),
    );
    await col
        .doc(dateKey)
        .set(finalized.toFirestore(), SetOptions(merge: true));
  }

  Future<void> refreshForToday() async {
    if (_isRefreshingForToday) return;
    final uid = _uid;
    if (uid == null) return;
    final loadGeneration = ++_stateGeneration;
    _isRefreshingForToday = true;
    try {
      while (_activeSaves.isNotEmpty) {
        await Future.wait(_activeSaves.toList());
      }
      // finalize の前に未確定の差分を totalEarned＋台帳へ確定させる。
      // これを飛ばすと finalizedEarnedYen(=provisional) と totalEarned が食い違う。
      await settlePendingLedger();
      final todayKey = HealthRollover.dateKey(DateTime.now());
      final col = _db.collection('users').doc(uid).collection('healthLogs');
      final currentDateKey = state.log.dateKey;
      if (HealthRollover.isPastDateKey(currentDateKey, todayKey)) {
        await _finalizeSavedLogForDate(col: col, dateKey: currentDateKey);
      }
      final pastResult = await _fetchPastLogs(col, todayKey);
      final doc = await col.doc(todayKey).get();
      if (_uid != uid || loadGeneration != _stateGeneration) return;
      final loadedLog = doc.exists
          ? HealthLog.fromFirestore(doc)
          : HealthLog(dateKey: todayKey);
      final settings = ref.read(userSettingsProvider).settings;
      final todayLog = await _syncTodayLogIfNeeded(
        uid: uid,
        log: loadedLog,
        settings: settings,
      );
      if (_uid != uid || loadGeneration != _stateGeneration) return;
      state = HealthDetailState(
        log: todayLog,
        isLoading: false,
        isEditableNow: true,
        errorMessage: pastResult.error,
        // baseline はロードした値（sync前）＝totalEarned 反映済みの額。
        lastSavedProvisionalYen: loadedLog.provisionalEarnedYen,
        historyLogs: pastResult.logs.take(14).toList(growable: false),
        isHistoryLoading: false,
        historyErrorMessage: null,
      );
    } catch (e) {
      if (_uid == uid && loadGeneration == _stateGeneration) {
        state = state.copyWith(
          errorMessage: '日付更新に失敗しました: $e',
          isHistoryLoading: false,
          historyLogs: const [],
        );
      }
    } finally {
      _isRefreshingForToday = false;
    }
  }

  // ── 公開API ───────────────────────────────────────────────
  /// ドラッグ中プレビュー。Firestore には書かない。所持金も変更しない。
  void previewValue(HealthCategory category, num value) {
    if (_isRefreshingForToday || !state.isEditableNow) return;
    final settings = ref.read(userSettingsProvider).settings;
    final base = _setValue(
      state.log,
      category,
      category.clampValue(value, settings),
    );
    final recomputed = _recompute(base, settings);
    state = state.copyWith(log: recomputed);
  }

  /// 確定保存（スライダーのドラッグ終了時）。healthLog の値だけを永続化し、
  /// 台帳・totalEarned は触らない。正味差分は退出時 [settlePendingLedger] で1件に集約。
  Future<void> commitValue(HealthCategory category, num value) async {
    if (_isRefreshingForToday || !state.isEditableNow) return;
    final uid = _uid;
    if (uid == null) return;
    final saveDateKey = state.log.dateKey;
    final saveGeneration = _stateGeneration;

    final settings = ref.read(userSettingsProvider).settings;
    final base = _setValue(
      state.log,
      category,
      category.clampValue(value, settings),
    );
    final recomputed = _recompute(base, settings);

    // 先に UI を更新
    state = state.copyWith(log: recomputed);

    // 値だけ保存（deltaYen: 0 → 台帳・残高はスキップ）。baseline も据え置く。
    try {
      await _trackActiveSave(
        _economyRepo.saveHealthLogAndAdjust(
          dateKey: recomputed.dateKey,
          healthLogData: recomputed.toFirestore(),
          deltaYen: 0,
        ),
      );
    } catch (e) {
      if (_shouldApplySaveResult(uid, saveDateKey, saveGeneration)) {
        state = state.copyWith(errorMessage: '保存に失敗しました: $e');
      }
    }
  }

  /// 退出（戻る／バックグラウンド／日付切替／破棄）時に呼ぶ。
  /// この滞在中に生じた provisional の正味差分を totalEarned に反映し、
  /// 冒険の記録（adventure_entries）へ**1件だけ**書き込む。差分が無ければ何もしない。
  Future<void> settlePendingLedger() async {
    final uid = _uid;
    if (uid == null) return;
    // 破棄済みで state 参照不可なら安全に打ち切る。
    final HealthDetailState current;
    try {
      current = state;
    } catch (_) {
      return;
    }
    if (current.log.isFinalized) return;
    final delta =
        current.log.provisionalEarnedYen - current.lastSavedProvisionalYen;
    if (delta == 0) return;
    final saveDateKey = current.log.dateKey;
    final saveGeneration = _stateGeneration;
    final logData = current.log.toFirestore();
    final settledProvisional = current.log.provisionalEarnedYen;
    try {
      await _trackActiveSave(
        _economyRepo.saveHealthLogAndAdjust(
          dateKey: saveDateKey,
          healthLogData: logData,
          deltaYen: delta,
        ),
      );
    } catch (e) {
      // 破棄後の state 書き込みは握り潰す（fire-and-forget 経路対策）。
      try {
        if (_shouldApplySaveResult(uid, saveDateKey, saveGeneration)) {
          state = state.copyWith(errorMessage: '保存に失敗しました: $e');
        }
      } catch (_) {}
      return;
    }
    try {
      if (_shouldApplySaveResult(uid, saveDateKey, saveGeneration)) {
        state = state.copyWith(lastSavedProvisionalYen: settledProvisional);
      }
    } catch (_) {}
  }

  // ── helpers ───────────────────────────────────────────────
  Future<HealthLog> _syncTodayLogIfNeeded({
    required String uid,
    required HealthLog log,
    required UserSettings settings,
  }) async {
    if (log.isFinalized) return log;
    final recomputed = _recompute(log, settings);
    if (!_computedFieldsDiffer(log, recomputed)) return log;

    // 目標変更等での再計算は値だけ保存（deltaYen: 0）。差分は退出時に集約する。
    // baseline は呼び出し元（_load / refreshForToday）がロード値に設定するため、
    // この再計算差分も退出時 settle で正しく1件に含まれる。
    await _trackActiveSave(
      _economyRepo.saveHealthLogAndAdjust(
        dateKey: recomputed.dateKey,
        healthLogData: recomputed.toFirestore(),
        deltaYen: 0,
      ),
    );
    if (_uid != uid) return log;
    return recomputed;
  }

  bool _computedFieldsDiffer(HealthLog a, HealthLog b) {
    return a.mealScore != b.mealScore ||
        a.sleepScore != b.sleepScore ||
        a.exerciseScore != b.exerciseScore ||
        a.meditationScore != b.meditationScore ||
        a.totalScore != b.totalScore ||
        a.provisionalEarnedYen != b.provisionalEarnedYen;
  }

  bool _shouldApplySaveResult(
    String saveUid,
    String saveDateKey,
    int saveGeneration,
  ) {
    return HealthRollover.shouldApplySaveResult(
      saveUid: saveUid,
      currentUid: _uid,
      saveDateKey: saveDateKey,
      currentDateKey: state.log.dateKey,
      saveGeneration: saveGeneration,
      currentGeneration: _stateGeneration,
    );
  }

  Future<T> _trackActiveSave<T>(Future<T> saveFuture) async {
    final tracked = saveFuture.then<void>((_) {}, onError: (_) {});
    _activeSaves.add(tracked);
    try {
      return await saveFuture;
    } finally {
      _activeSaves.remove(tracked);
    }
  }

  HealthLog _setValue(HealthLog log, HealthCategory c, double v) {
    switch (c) {
      case HealthCategory.meal:
        return log.copyWith(mealGrams: v);
      case HealthCategory.exercise:
        return log.copyWith(exerciseMinutes: v);
      case HealthCategory.sleep:
        return log.copyWith(sleepMinutes: v);
      case HealthCategory.meditation:
        return log.copyWith(meditationMinutes: v);
    }
  }

  HealthLog _recompute(HealthLog log, UserSettings s) {
    final sleepGoalMin = s.sleepGoalHours * 60 + s.sleepGoalMinutesExtra;
    // 比率から直接スコアを算出する。`level × weight` だと小数点切り捨ての
    // ズレで点数が目標達成度を正確に反映しないため。
    final mealScore = HealthScoring.score(log.mealGrams, s.mealGoalGrams, 3);
    final sleepScore = HealthScoring.score(
      log.sleepMinutes,
      sleepGoalMin,
      3,
      baseline: HealthCategoryX.sleepBaselineMinutes,
    );
    final exerciseScore = HealthScoring.score(
      log.exerciseMinutes,
      s.exerciseGoalMinutes,
      2,
    );
    final meditationScore = HealthScoring.score(
      log.meditationMinutes,
      s.meditationGoalMinutes,
      2,
    );
    final totalScore = mealScore + sleepScore + exerciseScore + meditationScore;
    final provisional = HealthScoring.earningsForPoints(
      totalScore,
      s.hourlyRate,
    );

    return log.copyWith(
      mealScore: mealScore,
      sleepScore: sleepScore,
      exerciseScore: exerciseScore,
      meditationScore: meditationScore,
      totalScore: totalScore,
      provisionalEarnedYen: provisional,
      updatedAt: DateTime.now(),
    );
  }
}

final healthDetailViewModelProvider =
    NotifierProvider<HealthDetailViewModel, HealthDetailState>(
      HealthDetailViewModel.new,
    );
