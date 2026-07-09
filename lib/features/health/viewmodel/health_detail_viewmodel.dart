import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';
import 'package:task_manager/features/economy/data/economy_repository.dart';
import 'package:task_manager/features/economy/providers/economy_providers.dart';
import 'package:task_manager/features/health/data/health_streak_repository.dart';
import 'package:task_manager/features/health/model/health_category.dart';
import 'package:task_manager/features/health/model/health_log.dart';
import 'package:task_manager/features/health/model/health_rollover.dart';
import 'package:task_manager/features/health/model/health_scoring.dart';
import 'package:task_manager/features/health/model/health_streak_engine.dart';
import 'package:task_manager/features/health/model/health_streak_state.dart';
import 'package:task_manager/features/health/providers/health_streak_providers.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';

class HealthDetailState {
  const HealthDetailState({
    required this.log,
    this.isLoading = false,
    this.isEditableNow = true,
    this.errorMessage,
    List<HealthLog> historyLogs = const [],
    bool isHistoryLoading = false,
    String? historyErrorMessage,
    HealthStreakState? streakState,
  }) : _historyLogs = historyLogs,
       _isHistoryLoading = isHistoryLoading,
       _historyErrorMessage = historyErrorMessage,
       _streakState = streakState;

  final HealthLog log;
  final bool isLoading;

  /// 当日判定（日付境界を越えたら false）
  final bool isEditableNow;

  final String? errorMessage;

  // Hot reload直後の古いStateインスタンスでも安全に読めるよう、
  // 追加フィールドはnullableで保持しつつ公開getterで既定値に寄せる。
  final List<HealthLog>? _historyLogs;
  final bool? _isHistoryLoading;
  final String? _historyErrorMessage;
  final HealthStreakState? _streakState;

  List<HealthLog> get historyLogs => _historyLogs ?? const [];
  bool get isHistoryLoading => _isHistoryLoading ?? false;
  String? get historyErrorMessage => _historyErrorMessage;

  /// ストリーク現況（連続日数・称号・フリーズ残）。非現金。
  HealthStreakState get streakState => _streakState ?? const HealthStreakState();

  HealthDetailState copyWith({
    HealthLog? log,
    bool? isLoading,
    bool? isEditableNow,
    String? errorMessage,
    List<HealthLog>? historyLogs,
    bool? isHistoryLoading,
    Object? historyErrorMessage = _unset,
    HealthStreakState? streakState,
  }) {
    return HealthDetailState(
      log: log ?? this.log,
      isLoading: isLoading ?? this.isLoading,
      isEditableNow: isEditableNow ?? this.isEditableNow,
      errorMessage: errorMessage,
      historyLogs: historyLogs ?? this.historyLogs,
      isHistoryLoading: isHistoryLoading ?? this.isHistoryLoading,
      historyErrorMessage: identical(historyErrorMessage, _unset)
          ? this.historyErrorMessage
          : historyErrorMessage as String?,
      streakState: streakState ?? this.streakState,
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

  /// ストリーク状態（`users/{uid}/healthState/streak`）の read/write。
  /// お金に触れない（非現金）ため economy のトランザクションとは独立。
  late HealthStreakRepository _streakRepo;

  @override
  HealthDetailState build() {
    _economyRepo = ref.read(economyRepositoryProvider);
    _streakRepo = ref.read(healthStreakRepositoryProvider);
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
        a.meditationEnabled != b.meditationEnabled ||
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
    try {
      // C-1対策：旧モデル（日中に残高反映）からの移行スイープを最初に一度だけ実行。
      // 冪等（healthMigratedV2 フラグ）なので毎回awaitして問題ない。
      await _economyRepo.migrateHealthBalanceV2();
      if (_uid != uid || loadGeneration != _stateGeneration) return;
      final todayKey = HealthRollover.dateKey(DateTime.now());
      final col = _db.collection('users').doc(uid).collection('healthLogs');
      final pastResult = await _fetchPastLogs(col, todayKey);
      // finalize後にストリークを前進させる（Step14）。
      final streakState = await _advanceStreakIfNeeded(uid);
      if (_uid != uid || loadGeneration != _stateGeneration) return;

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
        historyLogs: pastResult.logs.take(14).toList(growable: false),
        isHistoryLoading: false,
        historyErrorMessage: null,
        streakState: streakState,
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

  /// 過去ログを最大20件フェッチし、未確定ログを [EconomyRepository.finalizeHealthLog]
  /// で1日ずつ確定させる（Design A：ここで初めて残高へ加算される）。
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

      final logs = <HealthLog>[];
      for (final doc in snaps.docs) {
        var log = HealthLog.fromFirestore(doc);
        if (!log.isFinalized) {
          await _economyRepo.finalizeHealthLog(dateKey: log.dateKey);
          // 再フェッチせず、確定後の状態をローカルで反映する（finalizeHealthLogと同じ計算）。
          final add = (log.provisionalEarnedYen - log.balanceAppliedYen) > 0
              ? log.provisionalEarnedYen - log.balanceAppliedYen
              : 0;
          log = log.copyWith(
            isFinalized: true,
            finalizedEarnedYen: log.provisionalEarnedYen,
            balanceAppliedYen: log.balanceAppliedYen + add,
            finalizedAt: DateTime.now(),
          );
        }
        logs.add(log);
      }
      return (logs: logs, error: null);
    } catch (e) {
      return (logs: <HealthLog>[], error: '過去の健康ログ確定に失敗しました: $e');
    }
  }

  /// ストリーク（連続達成）を前進させる。finalize後（過去ログ確定後）に呼ぶ。
  /// お金には一切触れない（非現金：称号＋フリーズのみ）。
  ///
  /// - 初回（`lastProcessedDateKey==null`）は遡及しない：ベースラインを昨日に設定して終了（§10）。
  /// - 長期放置（from < 昨日-90日）も遡及しない：ベースラインを昨日に再設定する（M-1ガード）。
  /// - それ以外は `from+1 .. 昨日` を1日ずつ列挙し、各日の healthLog（無ければ ratio=0）で
  ///   [advanceOneDay] を適用する。ログ取得は `_fetchPastLogs`（表示用20件）に依存せず、
  ///   dateKey の専用レンジクエリで対象範囲の全ログを取る（M-1対策）。
  /// - 各日の outcome は対応する healthLog（無ければスタブ）へ書き込む。
  Future<HealthStreakState> _advanceStreakIfNeeded(String uid) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayKey = HealthRollover.dateKey(yesterday);
    final todayKey = HealthRollover.dateKey(today);

    var streak = await _streakRepo.load();

    final lastProcessed = streak.lastProcessedDateKey;
    if (lastProcessed == null) {
      // 初回は遡及しない。ベースラインだけ設定して終了。
      streak = streak.copyWith(lastProcessedDateKey: yesterdayKey);
      await _streakRepo.save(streak);
      return streak;
    }

    if (lastProcessed.compareTo(yesterdayKey) >= 0) {
      // 既に前進済み（同日内の複数回呼び出し等）。冪等に何もしない。
      return streak;
    }

    final fromDate = _parseDateKey(lastProcessed).add(const Duration(days: 1));
    final guardDate = today.subtract(const Duration(days: 91));
    if (fromDate.isBefore(guardDate)) {
      // M-1：長期放置は遡及せずベースラインを再設定する（streakは据え置き）。
      streak = streak.copyWith(lastProcessedDateKey: yesterdayKey);
      await _streakRepo.save(streak);
      return streak;
    }

    final fromKey = HealthRollover.dateKey(fromDate);
    final col = _db.collection('users').doc(uid).collection('healthLogs');
    final snaps = await col
        .where('dateKey', isGreaterThanOrEqualTo: fromKey)
        .where('dateKey', isLessThan: todayKey)
        .get();
    final logsByKey = {
      for (final d in snaps.docs) d.id: HealthLog.fromFirestore(d),
    };

    final outcomes = <String, String>{};
    var cursor = fromDate;
    while (!cursor.isAfter(yesterday)) {
      final dateKey = HealthRollover.dateKey(cursor);
      final monthKey =
          '${cursor.year.toString().padLeft(4, '0')}-${cursor.month.toString().padLeft(2, '0')}';
      final log = logsByKey[dateKey];
      final ratio = log?.achievedPercent ?? 0.0;
      final isPerfect = ratio >= 1.0;
      final result = advanceOneDay(
        streak,
        DayInput(
          dateKey: dateKey,
          ratio: ratio,
          isPerfect: isPerfect,
          monthKey: monthKey,
        ),
      );
      streak = result.state;
      outcomes[dateKey] = result.outcome;
      cursor = cursor.add(const Duration(days: 1));
    }

    streak = streak.copyWith(lastProcessedDateKey: yesterdayKey);
    await _streakRepo.save(streak);
    await _writeDayOutcomes(uid, outcomes);
    return streak;
  }

  /// 各日の outcome を対応する healthLog へ書き込む（無ければスタブ log を作成）。
  /// merge のため既存フィールド（achievedPercent 等）は上書きしない。
  Future<void> _writeDayOutcomes(String uid, Map<String, String> outcomes) async {
    if (outcomes.isEmpty) return;
    final col = _db.collection('users').doc(uid).collection('healthLogs');
    final batch = _db.batch();
    outcomes.forEach((dateKey, outcome) {
      batch.set(col.doc(dateKey), {
        'dateKey': dateKey,
        'dayOutcome': outcome,
      }, SetOptions(merge: true));
    });
    await batch.commit();
  }

  DateTime _parseDateKey(String key) {
    final parts = key.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// カレンダー表示用：[monthAnchor] の年月に属する healthLogs を
  /// dateKey → HealthLog のマップで返す。
  Future<Map<String, HealthLog>> fetchMonthLogs(DateTime monthAnchor) async {
    final uid = _uid;
    if (uid == null) return {};
    final start = DateTime(monthAnchor.year, monthAnchor.month, 1);
    final end = DateTime(monthAnchor.year, monthAnchor.month + 1, 1);
    final startKey = HealthRollover.dateKey(start);
    final endKey = HealthRollover.dateKey(end);
    final col = _db.collection('users').doc(uid).collection('healthLogs');
    final snaps = await col
        .where('dateKey', isGreaterThanOrEqualTo: startKey)
        .where('dateKey', isLessThan: endKey)
        .get();
    return {for (final d in snaps.docs) d.id: HealthLog.fromFirestore(d)};
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
      // Design A：日中は残高に触れない。settlePendingLedgerは値の保存のみ（no-op寄り）。
      await settlePendingLedger();
      final todayKey = HealthRollover.dateKey(DateTime.now());
      final col = _db.collection('users').doc(uid).collection('healthLogs');
      final currentDateKey = state.log.dateKey;
      if (HealthRollover.isPastDateKey(currentDateKey, todayKey)) {
        // 過去日となった当日ログを確定（ここで初めて残高へ加算される）。
        await _economyRepo.finalizeHealthLog(dateKey: currentDateKey);
      }
      final pastResult = await _fetchPastLogs(col, todayKey);
      // finalize後にストリークを前進させる（Step14）。
      final streakState = await _advanceStreakIfNeeded(uid);
      if (_uid != uid || loadGeneration != _stateGeneration) return;
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
        historyLogs: pastResult.logs.take(14).toList(growable: false),
        isHistoryLoading: false,
        historyErrorMessage: null,
        streakState: streakState,
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
  /// Design A：日中は残高・台帳に一切触れない。previewValue（ドラッグ中プレビュー）が
  /// 未保存のまま画面が破棄された場合に備え、現在の値だけを deltaYen:0 で保存する
  /// （commitValueで既に保存済みなら実質的に冪等な上書き）。
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
    final saveDateKey = current.log.dateKey;
    final saveGeneration = _stateGeneration;
    final logData = current.log.toFirestore();
    try {
      await _trackActiveSave(
        _economyRepo.saveHealthLogAndAdjust(
          dateKey: saveDateKey,
          healthLogData: logData,
          deltaYen: 0,
        ),
      );
    } catch (e) {
      // 破棄後の state 書き込みは握り潰す（fire-and-forget 経路対策）。
      try {
        if (_shouldApplySaveResult(uid, saveDateKey, saveGeneration)) {
          state = state.copyWith(errorMessage: '保存に失敗しました: $e');
        }
      } catch (_) {}
    }
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
    // 瞑想OFF時は合計・達成率・満点から瞑想を除外する（meditationScore自体は保存する）。
    final totalScore =
        mealScore + sleepScore + exerciseScore +
        (s.meditationEnabled ? meditationScore : 0);
    final achievedPercent = HealthScoring.achievementRatio(
      totalScore,
      s.maxActiveHealthScore,
    );
    final provisional = HealthScoring.earningsForRatio(
      ratio: achievedPercent,
      dailyCapYen: s.healthDailyCapYen,
    );

    return log.copyWith(
      mealScore: mealScore,
      sleepScore: sleepScore,
      exerciseScore: exerciseScore,
      meditationScore: meditationScore,
      totalScore: totalScore,
      provisionalEarnedYen: provisional,
      updatedAt: DateTime.now(),
      achievedPercent: achievedPercent,
      meditationEnabledSnapshot: s.meditationEnabled,
    );
  }
}

final healthDetailViewModelProvider =
    NotifierProvider<HealthDetailViewModel, HealthDetailState>(
      HealthDetailViewModel.new,
    );
