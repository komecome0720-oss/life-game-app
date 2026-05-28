import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';
import 'package:task_manager/features/health/model/health_category.dart';
import 'package:task_manager/features/health/model/health_log.dart';
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
  });

  final HealthLog log;
  final bool isLoading;

  /// 当日判定（日付境界を越えたら false）
  final bool isEditableNow;

  final String? errorMessage;

  /// 直近の Firestore 書き込み時点の provisional。totalEarned 差分計算に使用。
  final int lastSavedProvisionalYen;

  HealthDetailState copyWith({
    HealthLog? log,
    bool? isLoading,
    bool? isEditableNow,
    String? errorMessage,
    int? lastSavedProvisionalYen,
  }) {
    return HealthDetailState(
      log: log ?? this.log,
      isLoading: isLoading ?? this.isLoading,
      isEditableNow: isEditableNow ?? this.isEditableNow,
      errorMessage: errorMessage,
      lastSavedProvisionalYen:
          lastSavedProvisionalYen ?? this.lastSavedProvisionalYen,
    );
  }
}

class HealthDetailViewModel extends Notifier<HealthDetailState> {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  String? get _uid => _auth.currentUser?.uid;

  Timer? _midnightTimer;

  @override
  HealthDetailState build() {
    ref.onDispose(() {
      _midnightTimer?.cancel();
    });
    // ログイン状態（uid）の変化を購読し、サインイン直後に再ビルド→再ロードする。
    final uid = ref.watch(
      authStateProvider.select((async) => async.asData?.value?.uid),
    );
    _scheduleMidnightLock();
    // 目標値や時間単価が変わったら、再計算して保存する。
    ref.listen<UserSettingsState>(userSettingsProvider, (prev, next) {
      if (prev == null) return;
      if (_goalsAffectScore(prev.settings, next.settings)) {
        _onGoalsChanged();
      }
    });
    final emptyLog = HealthLog(dateKey: _todayKey(DateTime.now()));
    if (uid == null) {
      return HealthDetailState(log: emptyLog, isLoading: false);
    }
    // 初期ロードは非同期。現時点は今日の空ログで isLoading=true。
    Future.microtask(() => _load(uid));
    return HealthDetailState(log: emptyLog, isLoading: true);
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
    if (state.isLoading || !state.isEditableNow || state.log.isFinalized) {
      return;
    }
    final uid = _uid;
    if (uid == null) return;
    final settings = ref.read(userSettingsProvider).settings;
    final recomputed = _recompute(state.log, settings);
    if (recomputed.totalScore == state.log.totalScore &&
        recomputed.provisionalEarnedYen == state.log.provisionalEarnedYen) {
      return;
    }
    final lastSaved = state.lastSavedProvisionalYen;
    final delta = recomputed.provisionalEarnedYen - lastSaved;
    state = state.copyWith(log: recomputed);
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('healthLogs')
          .doc(recomputed.dateKey)
          .set(recomputed.toFirestore(), SetOptions(merge: true));
      state = state.copyWith(
        lastSavedProvisionalYen: recomputed.provisionalEarnedYen,
      );
      if (delta != 0) {
        await ref.read(userSettingsProvider.notifier).adjustBalance(delta);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: '保存に失敗しました: $e');
    }
  }

  static String _todayKey(DateTime now) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${now.year.toString().padLeft(4, '0')}-${pad(now.month)}-${pad(now.day)}';
  }

  void _scheduleMidnightLock() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final delay = nextMidnight.difference(now) + const Duration(seconds: 1);
    _midnightTimer = Timer(delay, () async {
      // 当日ログを確定して編集不可へ
      await _finalizeToday();
      state = state.copyWith(isEditableNow: false);
    });
  }

  Future<void> _load(String uid) async {
    final todayKey = _todayKey(DateTime.now());
    try {
      final col = _db.collection('users').doc(uid).collection('healthLogs');
      // 過去日ログで未確定のものを確定（最大5件）
      await _finalizePastLogs(col, todayKey);

      final doc = await col.doc(todayKey).get();
      // ロード中にユーザーが切り替わった場合は破棄
      if (_uid != uid) return;
      final HealthLog log = doc.exists
          ? HealthLog.fromFirestore(doc)
          : HealthLog(dateKey: todayKey);

      state = HealthDetailState(
        log: log,
        isLoading: false,
        isEditableNow: true,
        lastSavedProvisionalYen: log.provisionalEarnedYen,
      );
    } catch (e) {
      if (_uid != uid) return;
      state = state.copyWith(isLoading: false, errorMessage: '読み込みに失敗しました: $e');
    }
  }

  Future<void> _finalizePastLogs(
      CollectionReference<Map<String, dynamic>> col, String todayKey) async {
    try {
      final snaps = await col
          .where('isFinalized', isEqualTo: false)
          .where(FieldPath.documentId, isLessThan: todayKey)
          .limit(5)
          .get();
      for (final doc in snaps.docs) {
        final log = HealthLog.fromFirestore(doc);
        await doc.reference.set(
          log
              .copyWith(
                isFinalized: true,
                finalizedEarnedYen: log.provisionalEarnedYen,
                finalizedAt: DateTime.now(),
              )
              .toFirestore(),
          SetOptions(merge: true),
        );
      }
    } catch (_) {
      // 失敗しても致命的ではないため無視
    }
  }

  Future<void> _finalizeToday() async {
    final uid = _uid;
    if (uid == null) return;
    final log = state.log;
    if (log.isFinalized) return;
    final finalized = log.copyWith(
      isFinalized: true,
      finalizedEarnedYen: log.provisionalEarnedYen,
      finalizedAt: DateTime.now(),
    );
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('healthLogs')
          .doc(finalized.dateKey)
          .set(finalized.toFirestore(), SetOptions(merge: true));
      state = state.copyWith(log: finalized);
    } catch (_) {}
  }

  // ── 公開API ───────────────────────────────────────────────
  /// ドラッグ中プレビュー。Firestore には書かない。所持金も変更しない。
  void previewValue(HealthCategory category, int value) {
    if (!state.isEditableNow) return;
    final settings = ref.read(userSettingsProvider).settings;
    final base = _setValue(state.log, category, value);
    final recomputed = _recompute(base, settings);
    state = state.copyWith(log: recomputed);
  }

  /// 確定保存（スライダーのドラッグ終了時）。Firestore 書き込み＋totalEarned 差分更新。
  Future<void> commitValue(HealthCategory category, int value) async {
    if (!state.isEditableNow) return;
    final uid = _uid;
    if (uid == null) return;

    final settings = ref.read(userSettingsProvider).settings;
    final base = _setValue(state.log, category, value);
    final recomputed = _recompute(base, settings);
    final lastSaved = state.lastSavedProvisionalYen;
    final delta = recomputed.provisionalEarnedYen - lastSaved;

    // 先に UI を更新
    state = state.copyWith(log: recomputed);

    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('healthLogs')
          .doc(recomputed.dateKey)
          .set(recomputed.toFirestore(), SetOptions(merge: true));
      state = state.copyWith(lastSavedProvisionalYen: recomputed.provisionalEarnedYen);
      if (delta != 0) {
        await ref.read(userSettingsProvider.notifier).adjustBalance(delta);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: '保存に失敗しました: $e');
    }
  }

  // ── helpers ───────────────────────────────────────────────
  HealthLog _setValue(HealthLog log, HealthCategory c, int v) {
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
    final sleepScore = HealthScoring.score(log.sleepMinutes, sleepGoalMin, 3);
    final exerciseScore =
        HealthScoring.score(log.exerciseMinutes, s.exerciseGoalMinutes, 2);
    final meditationScore = HealthScoring.score(
        log.meditationMinutes, s.meditationGoalMinutes, 2);
    final totalScore =
        mealScore + sleepScore + exerciseScore + meditationScore;
    final provisional =
        HealthScoring.earningsForPoints(totalScore, s.hourlyRate);

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
