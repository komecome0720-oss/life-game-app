import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_settings.dart';
import 'package:task_manager/features/timer/model/active_timer.dart';
import 'package:task_manager/features/timer/model/pomodoro_run.dart';

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
    );
    return (timer: timer, write: _docRef(uid).set(timer.toMap()));
  }

  /// 一時停止：経過分を accumulatedSeconds に加算し、startedAtUtc を null にする。
  Future<void> pause(ActiveTimer t) async {
    final uid = _uidOrThrow;
    final elapsed = t.elapsedSeconds(_now());
    await _docRef(uid).update({
      'accumulatedSeconds': elapsed,
      'startedAtUtc': null,
      'updatedAtUtc': Timestamp.fromDate(_now().toUtc()),
    });
  }

  /// 再開：startedAtUtc を現在時刻にする（accumulatedSeconds はそのまま）。
  Future<void> resume(ActiveTimer t) async {
    final uid = _uidOrThrow;
    await _docRef(uid).update({
      'startedAtUtc': Timestamp.fromDate(_now().toUtc()),
      'updatedAtUtc': Timestamp.fromDate(_now().toUtc()),
    });
  }

  /// 保存後の状態：accumulatedSeconds=0・停止状態にリセットする。
  Future<void> resetToZero() async {
    final uid = _uidOrThrow;
    await _docRef(uid).update({
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
  Future<ActiveTimer> startPomodoro({
    required String taskId,
    required bool isTodo,
    required String taskTitle,
    required int predictedMinutes,
    required PomodoroSettings settings,
    required int baseActualMinutes,
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
      ),
    );
    await ref.set(timer.toMap());
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
      ),
    );
    return (timer: timer, write: _docRef(uid).set(timer.toMap()));
  }

  /// ポモドーロの一時停止：現フェーズの経過秒を phaseAccumulatedSeconds に確定し、
  /// phaseStartedAtUtc を null にする。
  Future<void> pausePomodoro(ActiveTimer t, int elapsedSecondsInPhase) async {
    final uid = _uidOrThrow;
    await _docRef(uid).update({
      'pomodoro.phaseAccumulatedSeconds': elapsedSecondsInPhase,
      'pomodoro.phaseStartedAtUtc': null,
      'updatedAtUtc': Timestamp.fromDate(_now().toUtc()),
    });
  }

  /// ポモドーロの再開：phaseStartedAtUtc を現在時刻にする
  /// （phaseAccumulatedSeconds はそのまま）。
  Future<void> resumePomodoro() async {
    final uid = _uidOrThrow;
    await _docRef(uid).update({
      'pomodoro.phaseStartedAtUtc': Timestamp.fromDate(_now().toUtc()),
      'updatedAtUtc': Timestamp.fromDate(_now().toUtc()),
    });
  }

  /// タスク名変更時にフォールバック表示用の taskTitle を追従させる。
  Future<void> updateTaskTitle(String title) async {
    final uid = _uidOrThrow;
    await _docRef(uid).update({
      'taskTitle': title,
      'updatedAtUtc': Timestamp.fromDate(_now().toUtc()),
    });
  }

  /// ロック画面での「現状」手動編集。
  ///
  /// フェーズ遷移（savedWorkPhases の増加）と競合しないよう、トランザクション内で
  /// doc の savedWorkPhases / workMinutes を読み直して
  /// base = max(0, newTotalMinutes - saved * work) を計算して書く。
  /// 戻り値は (確定した base, 実効合計 base + saved * work)。doc が無い/ポモドーロで
  /// ない場合は null。
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
      final completed = run.savedWorkPhases * run.workMinutes;
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
  Future<bool> commitPomodoroTransition({
    required int expectedCurrentPhaseIndex,
    required int newPhaseIndex,
    required DateTime? phaseStartedAtUtc,
    required int newSavedWorkPhases,
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

      tx.update(ref, {
        'pomodoro.phaseIndex': newPhaseIndex,
        'pomodoro.phaseStartedAtUtc': phaseStartedAtUtc == null
            ? null
            : Timestamp.fromDate(phaseStartedAtUtc.toUtc()),
        'pomodoro.phaseAccumulatedSeconds': 0,
        'pomodoro.savedWorkPhases': newSavedWorkPhases,
        'updatedAtUtc': Timestamp.fromDate(_now().toUtc()),
      });
      return true;
    });
  }
}
