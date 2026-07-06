import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_settings.dart';
import 'package:task_manager/features/timer/data/active_timer_repository.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  const uid = 'test-uid';

  late FakeFirebaseFirestore firestore;
  late DateTime clock;
  late ActiveTimerRepository repo;

  Future<Map<String, dynamic>?> rawDoc() async {
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('active_timer')
        .doc('current')
        .get();
    return snap.data();
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = _MockFirebaseAuth();
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
    clock = DateTime.utc(2026, 7, 6, 10, 0, 0);
    repo = ActiveTimerRepository(db: firestore, auth: auth, now: () => clock);
  });

  group('startPomodoro', () {
    test('未存在なら新規作成し、phaseIndex=0・実行中・baseActualMinutesを保持する', () async {
      final timer = await repo.startPomodoro(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
        settings: PomodoroSettings.defaults,
        baseActualMinutes: 30,
      );

      expect(timer.pomodoro, isNotNull);
      expect(timer.pomodoro!.phaseIndex, 0);
      expect(timer.pomodoro!.isRunning, isTrue);
      expect(timer.pomodoro!.baseActualMinutes, 30);
      expect(timer.pomodoro!.workMinutes, PomodoroSettings.defaultWorkMinutes);
      // 通常タイマー用フィールドは未使用のまま。
      expect(timer.startedAtUtc, isNull);
      expect(timer.accumulatedSeconds, 0);

      final data = await rawDoc();
      expect(data!['pomodoro'], isNotNull);
    });

    test('既存ドキュメントがあれば上書きせずそれを返す', () async {
      await repo.startPomodoro(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
        settings: PomodoroSettings.defaults,
        baseActualMinutes: 0,
      );
      final second = await repo.startPomodoro(
        taskId: 'task-2',
        isTodo: true,
        taskTitle: '別タスク',
        predictedMinutes: 30,
        settings: PomodoroSettings.defaults,
        baseActualMinutes: 99,
      );
      expect(second.taskId, 'task-1');
      expect(second.pomodoro!.baseActualMinutes, 0);
    });
  });

  group('startPomodoroLocalFirst', () {
    test('設定を反映したPomodoroRun付きtimerを即時返し、write完了後にdocが存在する', () async {
      final started = repo.startPomodoroLocalFirst(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
        settings: PomodoroSettings.defaults,
        baseActualMinutes: 30,
      );

      expect(started.timer.pomodoro, isNotNull);
      expect(started.timer.pomodoro!.phaseIndex, 0);
      expect(started.timer.pomodoro!.isRunning, isTrue);
      expect(started.timer.pomodoro!.baseActualMinutes, 30);
      expect(
        started.timer.pomodoro!.workMinutes,
        PomodoroSettings.defaultWorkMinutes,
      );
      expect(started.timer.startedAtUtc, isNull);

      await started.write;
      final data = await rawDoc();
      expect(data!['pomodoro'], isNotNull);
      expect(data['taskId'], 'task-1');
    });
  });

  group('pausePomodoro / resumePomodoro', () {
    test('pausePomodoroでphaseAccumulatedSecondsが確定しphaseStartedAtUtcがnullになる',
        () async {
      final timer = await repo.startPomodoro(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
        settings: PomodoroSettings.defaults,
        baseActualMinutes: 0,
      );
      await repo.pausePomodoro(timer, 123);

      final data = await rawDoc();
      final pomo = data!['pomodoro'] as Map<String, dynamic>;
      expect(pomo['phaseAccumulatedSeconds'], 123);
      expect(pomo['phaseStartedAtUtc'], isNull);
    });

    test('resumePomodoroでphaseStartedAtUtcが現在時刻になる', () async {
      final timer = await repo.startPomodoro(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
        settings: PomodoroSettings.defaults,
        baseActualMinutes: 0,
      );
      await repo.pausePomodoro(timer, 10);
      clock = clock.add(const Duration(minutes: 1));
      await repo.resumePomodoro();

      final data = await rawDoc();
      final pomo = data!['pomodoro'] as Map<String, dynamic>;
      expect(pomo['phaseStartedAtUtc'], isNotNull);
    });
  });

  group('commitPomodoroTransition', () {
    test('期待するphaseIndexと一致すれば更新しtrueを返す', () async {
      await repo.startPomodoro(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
        settings: PomodoroSettings.defaults,
        baseActualMinutes: 0,
      );

      final newStart = clock.add(const Duration(minutes: 25));
      final ok = await repo.commitPomodoroTransition(
        expectedCurrentPhaseIndex: 0,
        newPhaseIndex: 1,
        phaseStartedAtUtc: newStart,
        newSavedWorkPhases: 1,
      );
      expect(ok, isTrue);

      final data = await rawDoc();
      final pomo = data!['pomodoro'] as Map<String, dynamic>;
      expect(pomo['phaseIndex'], 1);
      expect(pomo['savedWorkPhases'], 1);
      expect(pomo['phaseAccumulatedSeconds'], 0);
    });

    test('期待するphaseIndexと不一致なら何もせずfalseを返す（冪等性）', () async {
      await repo.startPomodoro(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
        settings: PomodoroSettings.defaults,
        baseActualMinutes: 0,
      );
      // 既に他端末が phaseIndex=1 へ進めた後だと仮定して expected=0 で呼ぶと
      // 実際には doc は phaseIndex=0 のままなので一致するはずが、
      // ここでは逆に doc 側を先に進めてから expected=0 を渡し不一致を再現する。
      await repo.commitPomodoroTransition(
        expectedCurrentPhaseIndex: 0,
        newPhaseIndex: 1,
        phaseStartedAtUtc: clock,
        newSavedWorkPhases: 1,
      );

      final ok = await repo.commitPomodoroTransition(
        expectedCurrentPhaseIndex: 0, // 既に1のはずなので不一致
        newPhaseIndex: 1,
        phaseStartedAtUtc: clock,
        newSavedWorkPhases: 5,
      );
      expect(ok, isFalse);

      final data = await rawDoc();
      final pomo = data!['pomodoro'] as Map<String, dynamic>;
      expect(pomo['savedWorkPhases'], 1); // 上書きされていない
    });

    test('phaseStartedAtUtc=null なら一時停止状態で遷移する（休憩スキップ・復元用）',
        () async {
      await repo.startPomodoro(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
        settings: PomodoroSettings.defaults,
        baseActualMinutes: 0,
      );
      final ok = await repo.commitPomodoroTransition(
        expectedCurrentPhaseIndex: 0,
        newPhaseIndex: 1,
        phaseStartedAtUtc: null,
        newSavedWorkPhases: 1,
      );
      expect(ok, isTrue);

      final data = await rawDoc();
      final pomo = data!['pomodoro'] as Map<String, dynamic>;
      expect(pomo['phaseStartedAtUtc'], isNull);
    });

    test('pomodoroドキュメントが存在しなければfalseを返す', () async {
      final ok = await repo.commitPomodoroTransition(
        expectedCurrentPhaseIndex: 0,
        newPhaseIndex: 1,
        phaseStartedAtUtc: clock,
        newSavedWorkPhases: 1,
      );
      expect(ok, isFalse);
    });
  });

  group('updateTaskTitle', () {
    test('taskTitleとupdatedAtUtcのみ更新され、pomodoro進行状態は変わらない', () async {
      await repo.startPomodoro(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
        settings: PomodoroSettings.defaults,
        baseActualMinutes: 30,
      );
      await repo.commitPomodoroTransition(
        expectedCurrentPhaseIndex: 0,
        newPhaseIndex: 1,
        phaseStartedAtUtc: clock,
        newSavedWorkPhases: 1,
      );

      clock = clock.add(const Duration(minutes: 1));
      await repo.updateTaskTitle('新しいクエスト名');

      final data = await rawDoc();
      expect(data!['taskTitle'], '新しいクエスト名');
      expect(
        (data['updatedAtUtc'] as Timestamp).toDate().toUtc(),
        clock,
      );
      final pomo = data['pomodoro'] as Map<String, dynamic>;
      expect(pomo['phaseIndex'], 1);
      expect(pomo['savedWorkPhases'], 1);
      expect(pomo['baseActualMinutes'], 30);
    });
  });

  group('commitPomodoroBaseActualMinutes', () {
    test('通常更新: base = newTotal - saved*work が書かれ、戻り値のtotalMinutesが入力値と一致',
        () async {
      await repo.startPomodoro(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
        settings: PomodoroSettings.defaults,
        baseActualMinutes: 0,
      );
      // savedWorkPhases=1・workMinutes=既定値 にしておく。
      await repo.commitPomodoroTransition(
        expectedCurrentPhaseIndex: 0,
        newPhaseIndex: 1,
        phaseStartedAtUtc: clock,
        newSavedWorkPhases: 1,
      );
      final workMinutes = PomodoroSettings.defaultWorkMinutes;
      final newTotal = workMinutes + 20;

      final result = await repo.commitPomodoroBaseActualMinutes(
        newTotalMinutes: newTotal,
      );

      expect(result, isNotNull);
      expect(result!.baseActualMinutes, 20);
      expect(result.totalMinutes, newTotal);

      final data = await rawDoc();
      final pomo = data!['pomodoro'] as Map<String, dynamic>;
      expect(pomo['baseActualMinutes'], 20);
      expect(pomo['phaseIndex'], 1);
      expect(pomo['savedWorkPhases'], 1);
    });

    test('0クランプ: newTotal < saved*work のとき base=0、totalMinutesはsaved*work',
        () async {
      await repo.startPomodoro(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
        settings: PomodoroSettings.defaults,
        baseActualMinutes: 0,
      );
      await repo.commitPomodoroTransition(
        expectedCurrentPhaseIndex: 0,
        newPhaseIndex: 1,
        phaseStartedAtUtc: clock,
        newSavedWorkPhases: 1,
      );
      final workMinutes = PomodoroSettings.defaultWorkMinutes;

      final result = await repo.commitPomodoroBaseActualMinutes(
        newTotalMinutes: workMinutes - 5,
      );

      expect(result, isNotNull);
      expect(result!.baseActualMinutes, 0);
      expect(result.totalMinutes, workMinutes);

      final data = await rawDoc();
      final pomo = data!['pomodoro'] as Map<String, dynamic>;
      expect(pomo['baseActualMinutes'], 0);
    });

    test('docなしのときnullを返し何も書かない', () async {
      final result = await repo.commitPomodoroBaseActualMinutes(
        newTotalMinutes: 30,
      );
      expect(result, isNull);
      expect(await rawDoc(), isNull);
    });

    test('pomodoroなし（通常タイマー）のときnullを返し何も書かない', () async {
      await repo.start(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
      );

      final result = await repo.commitPomodoroBaseActualMinutes(
        newTotalMinutes: 30,
      );

      expect(result, isNull);
      final data = await rawDoc();
      expect(data!['pomodoro'], isNull);
    });

    test('phaseIndex / savedWorkPhases 等を壊さない', () async {
      await repo.startPomodoro(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
        settings: PomodoroSettings.defaults,
        baseActualMinutes: 0,
      );
      await repo.commitPomodoroTransition(
        expectedCurrentPhaseIndex: 0,
        newPhaseIndex: 2,
        phaseStartedAtUtc: clock,
        newSavedWorkPhases: 2,
      );

      final before = await rawDoc();
      final pomoBefore = before!['pomodoro'] as Map<String, dynamic>;

      await repo.commitPomodoroBaseActualMinutes(newTotalMinutes: 100);

      final after = await rawDoc();
      final pomoAfter = after!['pomodoro'] as Map<String, dynamic>;
      expect(pomoAfter['phaseIndex'], pomoBefore['phaseIndex']);
      expect(pomoAfter['savedWorkPhases'], pomoBefore['savedWorkPhases']);
      expect(pomoAfter['workMinutes'], pomoBefore['workMinutes']);
    });
  });
}
