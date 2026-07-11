import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:task_manager/features/health/model/health_rollover.dart';
import 'package:task_manager/features/pomodoro/data/pomodoro_day_repository.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_day.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_schedule.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_settings.dart';
import 'package:task_manager/features/timer/model/active_timer.dart';
import 'package:task_manager/features/timer/model/pomodoro_run.dart';

/// `commitPomodoroTransition` が day doc（`pomodoro_days/{dateKey}`）へ適用する
/// 差分。呼び出し元が「完走か・スキップか」を明示することで、セット数・作業秒を
/// フェーズ番号の範囲から誤って導出しないようにする
/// （スキップは phaseIndex が進んでも完走ではないため）。
class PomodoroDayDelta {
  const PomodoroDayDelta({
    required this.completedWorkPhasesDelta,
    required this.creditCycleProgress,
    required this.workSecondsDelta,
  });

  /// `completedSetsToday` に加算する数（スキップは常に0）。
  final int completedWorkPhasesDelta;

  /// true なら `[run.phaseIndex, newPhaseIndex)` を「完走扱い」で走査し、
  /// `cycleCompletedSets` を進める（work +1・長休憩通過で0リセット）。
  /// false（スキップ等）なら `cycleCompletedSets` は変更しない。
  final bool creditCycleProgress;

  /// `daily_earnings.workSeconds` へ加算する秒数（0以下は加算しない）。
  final int workSecondsDelta;
}

/// `users/{uid}/active_timer/current` を単一ドキュメントとして扱い、
/// 同時に1つのタイマーのみが存在することを保証するリポジトリ。
class ActiveTimerRepository {
  ActiveTimerRepository({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
    DateTime Function()? now,
  }) : _db = db ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _now = now ?? DateTime.now;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final DateTime Function() _now;

  static const _docId = 'current';

  DocumentReference<Map<String, dynamic>> _docRef(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('active_timer')
      .doc(_docId);

  String get _uidOrThrow {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    return uid;
  }

  /// 相手端末の削除競合で doc が消えていても落とさない update。
  /// not-found（相手が完了/クリアで delete 済み）は無視する。
  Future<void> _safeUpdate(String uid, Map<String, Object?> data) async {
    try {
      await _docRef(uid).update(data);
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') return; // doc は既に消えている＝この更新は無効でよい
      rethrow;
    }
  }

  /// 現在のアクティブタイマーを監視する。存在しなければ null を流す。
  Stream<ActiveTimer?> watch() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return _docRef(uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return ActiveTimer.fromMap(data);
    });
  }

  /// タイマーを開始する。既にドキュメントが存在する場合は上書きせずそれを返す
  /// （同時1タイマー保証・多重スタート防止）。
  Future<ActiveTimer> start({
    required String taskId,
    required bool isTodo,
    required String taskTitle,
    required int predictedMinutes,
    bool quickStart = false,
  }) async {
    final uid = _uidOrThrow;
    final ref = _docRef(uid);
    final existing = await ref.get();
    final existingData = existing.data();
    if (existingData != null) {
      return ActiveTimer.fromMap(existingData);
    }
    final timer = ActiveTimer(
      taskId: taskId,
      isTodo: isTodo,
      taskTitle: taskTitle,
      predictedMinutes: predictedMinutes,
      startedAtUtc: _now().toUtc(),
      accumulatedSeconds: 0,
      updatedAtUtc: _now().toUtc(),
      quickStart: quickStart,
    );
    await ref.set(timer.toMap());
    return timer;
  }

  /// タイマーをローカルファーストで開始する。
  ///
  /// 既存docの有無チェックは呼び出し側が `activeTimerStreamProvider` の最新値で
  /// 済ませる前提。書き込みを await せず ActiveTimer を即返すことで、スタート操作
  /// からロック画面表示までにネットワーク往復を挟まない（オフライン永続化により
  /// ローカルへは即時反映され、サーバへはバックグラウンドで同期される）。
  /// 戻り値の write は呼び出し側の失敗通知用。
  ({ActiveTimer timer, Future<void> write}) startLocalFirst({
    required String taskId,
    required bool isTodo,
    required String taskTitle,
    required int predictedMinutes,
    bool quickStart = false,
  }) {
    final uid = _uidOrThrow;
    final timer = ActiveTimer(
      taskId: taskId,
      isTodo: isTodo,
      taskTitle: taskTitle,
      predictedMinutes: predictedMinutes,
      startedAtUtc: _now().toUtc(),
      accumulatedSeconds: 0,
      updatedAtUtc: _now().toUtc(),
      quickStart: quickStart,
    );
    return (timer: timer, write: _docRef(uid).set(timer.toMap()));
  }

  /// 一時停止：経過分を accumulatedSeconds に加算し、startedAtUtc を null にする。
  Future<void> pause(ActiveTimer t) async {
    final uid = _uidOrThrow;
    final elapsed = t.elapsedSeconds(_now());
    await _safeUpdate(uid, {
      'accumulatedSeconds': elapsed,
      'startedAtUtc': null,
      'updatedAtUtc': Timestamp.fromDate(_now().toUtc()),
    });
  }

  /// 再開：startedAtUtc を現在時刻にする（accumulatedSeconds はそのまま）。
  Future<void> resume(ActiveTimer t) async {
    final uid = _uidOrThrow;
    await _safeUpdate(uid, {
      'startedAtUtc': Timestamp.fromDate(_now().toUtc()),
      'updatedAtUtc': Timestamp.fromDate(_now().toUtc()),
    });
  }

  /// 保存後の状態：accumulatedSeconds=0・停止状態にリセットする。
  Future<void> resetToZero() async {
    final uid = _uidOrThrow;
    await _safeUpdate(uid, {
      'accumulatedSeconds': 0,
      'startedAtUtc': null,
      'updatedAtUtc': Timestamp.fromDate(_now().toUtc()),
    });
  }

  /// タイマードキュメントを削除する（✕・完了時）。
  Future<void> clear() async {
    final uid = _uidOrThrow;
    await _docRef(uid).delete();
  }

  /// ポモドーロを開始する。既にドキュメントが存在する場合は上書きせずそれを返す
  /// （`start` と同じ方針。通常タイマー・ポモドーロどちらが残っていてもそれを尊重する）。
  ///
  /// [dayStart] を渡すと「1日通しセット」の開始位置（やりかけ作業フェーズの再開・
  /// 未消化休憩の消化）を反映し、day doc の消化書き戻し（`dayStart.dayAfter`）を
  /// timer doc の書き込みと同じ batch で行う。[dateKey] は [dayStart] を渡す場合
  /// 必須（day doc の参照先）。渡さない場合は既定（1セット目の先頭）で開始する。
  Future<ActiveTimer> startPomodoro({
    required String taskId,
    required bool isTodo,
    required String taskTitle,
    required int predictedMinutes,
    required PomodoroSettings settings,
    required int baseActualMinutes,
    String dateKey = '',
    PomodoroDayStart? dayStart,
    bool quickStart = false,
  }) async {
    final uid = _uidOrThrow;
    final ref = _docRef(uid);
    final existing = await ref.get();
    final existingData = existing.data();
    if (existingData != null) {
      return ActiveTimer.fromMap(existingData);
    }
    final nowUtc = _now().toUtc();
    final timer = ActiveTimer(
      taskId: taskId,
      isTodo: isTodo,
      taskTitle: taskTitle,
      predictedMinutes: predictedMinutes,
      startedAtUtc: null,
      accumulatedSeconds: 0,
      updatedAtUtc: nowUtc,
      pomodoro: PomodoroRun.start(
        settings: settings,
        baseActualMinutes: baseActualMinutes,
        nowUtc: nowUtc,
        dayStart: dayStart,
        dateKey: dateKey,
      ),
      quickStart: quickStart,
    );
    final batch = _db.batch();
    batch.set(ref, timer.toMap());
    if (dayStart != null) {
      batch.set(
        PomodoroDayRepository.docRef(_db, uid, dateKey),
        dayStart.dayAfter.toMap(),
      );
    }
    await batch.commit();
    return timer;
  }

  /// ポモドーロをローカルファーストで開始する（`startLocalFirst` と同じ方針）。
  ({ActiveTimer timer, Future<void> write}) startPomodoroLocalFirst({
    required String taskId,
    required bool isTodo,
    required String taskTitle,
    required int predictedMinutes,
    required PomodoroSettings settings,
    required int baseActualMinutes,
    String dateKey = '',
    PomodoroDayStart? dayStart,
    bool quickStart = false,
  }) {
    final uid = _uidOrThrow;
    final nowUtc = _now().toUtc();
    final timer = ActiveTimer(
      taskId: taskId,
      isTodo: isTodo,
      taskTitle: taskTitle,
      predictedMinutes: predictedMinutes,
      startedAtUtc: null,
      accumulatedSeconds: 0,
      updatedAtUtc: nowUtc,
      pomodoro: PomodoroRun.start(
        settings: settings,
        baseActualMinutes: baseActualMinutes,
        nowUtc: nowUtc,
        dayStart: dayStart,
        dateKey: dateKey,
      ),
      quickStart: quickStart,
    );
    final batch = _db.batch();
    batch.set(_docRef(uid), timer.toMap());
    if (dayStart != null) {
      batch.set(
        PomodoroDayRepository.docRef(_db, uid, dateKey),
        dayStart.dayAfter.toMap(),
      );
    }
    return (timer: timer, write: batch.commit());
  }

  /// ポモドーロの一時停止：現フェーズの経過秒を phaseAccumulatedSeconds に確定し、
  /// phaseStartedAtUtc を null にする。
  Future<void> pausePomodoro(ActiveTimer t, int elapsedSecondsInPhase) async {
    final uid = _uidOrThrow;
    await _safeUpdate(uid, {
      'pomodoro.phaseAccumulatedSeconds': elapsedSecondsInPhase,
      'pomodoro.phaseStartedAtUtc': null,
      'updatedAtUtc': Timestamp.fromDate(_now().toUtc()),
    });
  }

  /// ポモドーロの再開：phaseStartedAtUtc を現在時刻にする
  /// （phaseAccumulatedSeconds はそのまま）。
  Future<void> resumePomodoro() async {
    final uid = _uidOrThrow;
    await _safeUpdate(uid, {
      'pomodoro.phaseStartedAtUtc': Timestamp.fromDate(_now().toUtc()),
      'updatedAtUtc': Timestamp.fromDate(_now().toUtc()),
    });
  }

  /// タスク名変更時にフォールバック表示用の taskTitle を追従させる。
  Future<void> updateTaskTitle(String title) async {
    final uid = _uidOrThrow;
    await _safeUpdate(uid, {
      'taskTitle': title,
      'updatedAtUtc': Timestamp.fromDate(_now().toUtc()),
    });
  }

  /// ロック画面での「見込み」手動編集。
  Future<void> updatePredictedMinutes(int predictedMinutes) async {
    final uid = _uidOrThrow;
    await _safeUpdate(uid, {
      'predictedMinutes': predictedMinutes,
      'updatedAtUtc': Timestamp.fromDate(_now().toUtc()),
    });
  }

  /// ロック画面での「現状」手動編集。
  ///
  /// フェーズ遷移（savedWorkPhases の増加）と競合しないよう、トランザクション内で
  /// doc の creditedMinutes を読み直して base = max(0, newTotalMinutes - credited)
  /// を計算して書く（レビューM-2：旧 `savedWorkPhases * workMinutes` 再計算から
  /// `creditedMinutes` 参照に置換。スキップで creditedMinutes と savedWorkPhases×
  /// workMinutes が乖離するケースでも「現状」欄が正しい値を保つ）。
  /// 戻り値は (確定した base, 実効合計 base + creditedMinutes)。doc が無い/
  /// ポモドーロでない場合は null。
  Future<({int baseActualMinutes, int totalMinutes})?>
      commitPomodoroBaseActualMinutes({required int newTotalMinutes}) async {
    final uid = _uidOrThrow;
    final ref = _docRef(uid);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return null;
      final run = ActiveTimer.fromMap(data).pomodoro;
      if (run == null) return null;
      final completed = run.creditedMinutes;
      final base =
          (newTotalMinutes - completed) < 0 ? 0 : newTotalMinutes - completed;
      tx.update(ref, {
        'pomodoro.baseActualMinutes': base,
        'updatedAtUtc': Timestamp.fromDate(_now().toUtc()),
      });
      return (baseActualMinutes: base, totalMinutes: base + completed);
    });
  }

  /// フェーズ遷移をコミットする（ライブな遷移・休憩スキップ・復元いずれからも呼ぶ）。
  ///
  /// doc の phaseIndex が [expectedCurrentPhaseIndex] のときのみ更新する
  /// トランザクションとし、別端末との競合があっても冪等にする
  /// （既に他端末が同じ遷移をコミット済みなら何もしない）。
  ///
  /// [phaseStartedAtUtc] が null なら一時停止状態で新フェーズへ遷移する
  /// （休憩スキップ・復元の1フェーズ上限用）。非null なら実行中のまま遷移する
  /// （ライブな遷移コミット用。理論境界時刻を渡すことでドリフトを防ぐ）。
  ///
  /// [newCreditedMinutes] は run.creditedMinutes の新値（渡さなければ変更しない。
  /// スキップ・完走いずれも呼び出し元が明示的に計算した値を渡すこと）。
  /// [dayDelta] を渡すと `pomodoro_days/{run.dateKey}` と `daily_earnings` へも
  /// 同一トランザクションで反映する（**明示差分方式**：セット数・作業秒はフェーズ
  /// 番号の範囲から導出せず、常に呼び出し元が渡した差分を真実とする）。
  /// 期待 phaseIndex と不一致（＝他端末が既にコミット済み）のときは day doc も
  /// daily_earnings も一切触らない（冪等性維持。同じ遷移の二重コミット不可）。
  Future<bool> commitPomodoroTransition({
    required int expectedCurrentPhaseIndex,
    required int newPhaseIndex,
    required DateTime? phaseStartedAtUtc,
    required int newSavedWorkPhases,
    int? newCreditedMinutes,
    PomodoroDayDelta? dayDelta,
  }) async {
    final uid = _uidOrThrow;
    final ref = _docRef(uid);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return false;
      final current = ActiveTimer.fromMap(data);
      final run = current.pomodoro;
      if (run == null) return false;
      if (run.phaseIndex != expectedCurrentPhaseIndex) return false;

      DocumentReference<Map<String, dynamic>>? dayRef;
      PomodoroDay? dayBefore;
      if (dayDelta != null) {
        final dateKey =
            run.dateKey.isEmpty ? HealthRollover.dateKey(_now()) : run.dateKey;
        dayRef = PomodoroDayRepository.docRef(_db, uid, dateKey);
        final daySnap = await tx.get(dayRef);
        dayBefore =
            PomodoroDay.fromMap(daySnap.data()) ?? PomodoroDay.empty(_now().toUtc());
      }

      tx.update(ref, {
        'pomodoro.phaseIndex': newPhaseIndex,
        'pomodoro.phaseStartedAtUtc': phaseStartedAtUtc == null
            ? null
            : Timestamp.fromDate(phaseStartedAtUtc.toUtc()),
        'pomodoro.phaseAccumulatedSeconds': 0,
        'pomodoro.savedWorkPhases': newSavedWorkPhases,
        'pomodoro.creditedMinutes': ?newCreditedMinutes,
        'updatedAtUtc': Timestamp.fromDate(_now().toUtc()),
      });

      if (dayDelta != null && dayRef != null && dayBefore != null) {
        var cycleCompletedSets = dayBefore.cycleCompletedSets;
        if (dayDelta.creditCycleProgress) {
          final schedule = PomodoroSchedule(run);
          for (var i = run.phaseIndex; i < newPhaseIndex; i++) {
            final type = schedule.phaseTypeAt(i);
            if (type == PomodoroPhaseType.work) {
              cycleCompletedSets += 1;
            } else if (type == PomodoroPhaseType.longBreak) {
              cycleCompletedSets = 0;
            }
          }
        }
        tx.set(
          dayRef,
          dayBefore
              .copyWith(
                completedSetsToday: dayBefore.completedSetsToday +
                    dayDelta.completedWorkPhasesDelta,
                cycleCompletedSets: cycleCompletedSets,
                clearCarryWork: true,
                updatedAtUtc: _now().toUtc(),
              )
              .toMap(),
        );

        if (dayDelta.workSecondsDelta > 0) {
          final earningsRef = _db
              .collection('users')
              .doc(uid)
              .collection('daily_earnings')
              .doc(HealthRollover.dateKey(_now()));
          tx.set(
            earningsRef,
            {
              'workSeconds': FieldValue.increment(dayDelta.workSecondsDelta),
              'updatedAtUtc': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }
      return true;
    });
  }

  /// ✕・完了時のクローズ処理。トランザクションではなく batch
  /// （active_timer doc 削除は他端末との競合ガードが不要なため）。
  ///
  /// (a) day doc へ carryWork（work途中: elapsed / フェーズ長（override優先）/
  ///     creditedMinutes累計 = carriedInCreditedMinutes + このセッションの途中分round）
  ///     または pendingBreak（休憩中: isLong / 残秒 / sinceUtc=now）を書く。
  ///     書き込むものが無ければ（work先頭・carried0・途中0秒／休憩が消化済み）省略する。
  /// (b) daily_earnings.workSeconds へ [inProgressWorkSeconds] を increment
  ///     （>0のときのみ）。
  /// (c) active_timer doc を削除する。
  ///
  /// 何も書くものが無ければ (c) のみ＝実質 [clear] と同じ。
  /// [effective] は呼び出し元が `PomodoroSchedule.currentPhase(now)` で
  /// computed 済みの実効フェーズ状態、[inProgressWorkSeconds] は
  /// `PomodoroSchedule.inProgressSessionSeconds(effective)` の値を渡す。
  Future<void> closePomodoroRun({
    required ActiveTimer timer,
    required PomodoroPhaseState effective,
    required int inProgressWorkSeconds,
  }) async {
    final uid = _uidOrThrow;
    final run = timer.pomodoro;
    final batch = _db.batch();

    if (run != null) {
      final nowUtc = _now().toUtc();
      final dateKey =
          run.dateKey.isEmpty ? HealthRollover.dateKey(_now()) : run.dateKey;
      final dayRef = PomodoroDayRepository.docRef(_db, uid, dateKey);

      if (effective.type == PomodoroPhaseType.work) {
        // 経過0秒でも carried 持ちで開始して即✕なら carryWork を書き戻す
        // （レビューC-2：day doc 書き込みを省略しない）。
        if (effective.elapsedSeconds > 0 || run.carriedInSeconds > 0) {
          final creditedMinutes = run.carriedInCreditedMinutes +
              (inProgressWorkSeconds / 60).round();
          batch.set(
            dayRef,
            {
              'carryWork': PomodoroCarryWork(
                elapsedSeconds: effective.elapsedSeconds,
                phaseLengthSeconds: effective.phaseLengthSeconds,
                creditedMinutes: creditedMinutes,
              ).toMap(),
              'pendingBreak': null,
              'updatedAtUtc': Timestamp.fromDate(nowUtc),
            },
            SetOptions(merge: true),
          );
        }
      } else if (effective.remainingSeconds > 0) {
        batch.set(
          dayRef,
          {
            'pendingBreak': PomodoroPendingBreak(
              isLong: effective.type == PomodoroPhaseType.longBreak,
              remainingSeconds: effective.remainingSeconds,
              sinceUtc: nowUtc,
            ).toMap(),
            'carryWork': null,
            'updatedAtUtc': Timestamp.fromDate(nowUtc),
          },
          SetOptions(merge: true),
        );
      }

      if (inProgressWorkSeconds > 0) {
        final earningsRef = _db
            .collection('users')
            .doc(uid)
            .collection('daily_earnings')
            .doc(HealthRollover.dateKey(_now()));
        batch.set(
          earningsRef,
          {
            'workSeconds': FieldValue.increment(inProgressWorkSeconds),
            'updatedAtUtc': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    }

    batch.delete(_docRef(uid));
    await batch.commit();
  }
}
