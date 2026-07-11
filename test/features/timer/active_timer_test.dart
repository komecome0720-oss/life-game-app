import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/timer/model/active_timer.dart';

void main() {
  group('ActiveTimer.elapsedSeconds', () {
    test('running: accumulated + 実時間経過を加算する', () {
      final startedAt = DateTime.utc(2026, 7, 6, 10, 0, 0);
      final timer = ActiveTimer(
        taskId: 't1',
        isTodo: false,
        taskTitle: 'タスク',
        predictedMinutes: 60,
        startedAtUtc: startedAt,
        accumulatedSeconds: 120,
        updatedAtUtc: startedAt,
      );
      final now = DateTime.utc(2026, 7, 6, 10, 1, 30); // +90秒
      expect(timer.elapsedSeconds(now), 120 + 90);
    });

    test('paused: accumulatedSeconds のみを返す（startedAtUtc は無視）', () {
      final timer = ActiveTimer(
        taskId: 't1',
        isTodo: false,
        taskTitle: 'タスク',
        predictedMinutes: 60,
        startedAtUtc: null,
        accumulatedSeconds: 300,
        updatedAtUtc: DateTime.utc(2026, 7, 6),
      );
      expect(timer.elapsedSeconds(DateTime.utc(2026, 7, 6, 12)), 300);
      expect(timer.isRunning, isFalse);
    });

    test('端末時刻が巻き戻って負の経過になっても 0 にクランプする', () {
      final startedAt = DateTime.utc(2026, 7, 6, 10, 0, 0);
      final timer = ActiveTimer(
        taskId: 't1',
        isTodo: false,
        taskTitle: 'タスク',
        predictedMinutes: 60,
        startedAtUtc: startedAt,
        accumulatedSeconds: 10,
        updatedAtUtc: startedAt,
      );
      final past = DateTime.utc(2026, 7, 6, 9, 59, 0); // startedAtUtc より前
      expect(timer.elapsedSeconds(past), 10);
    });

    test('isRunning は startedAtUtc の有無で決まる', () {
      final running = ActiveTimer(
        taskId: 't1',
        isTodo: true,
        taskTitle: 'タスク',
        predictedMinutes: 30,
        startedAtUtc: DateTime.utc(2026, 7, 6),
        accumulatedSeconds: 0,
        updatedAtUtc: DateTime.utc(2026, 7, 6),
      );
      expect(running.isRunning, isTrue);
    });
  });

  group('ActiveTimer.fromMap / toMap', () {
    test('running な状態の往復変換', () {
      final startedAt = DateTime.utc(2026, 7, 6, 9, 0, 0);
      final updatedAt = DateTime.utc(2026, 7, 6, 9, 5, 0);
      final timer = ActiveTimer(
        taskId: 'task-123',
        isTodo: true,
        taskTitle: 'サンプルタスク',
        predictedMinutes: 45,
        startedAtUtc: startedAt,
        accumulatedSeconds: 30,
        updatedAtUtc: updatedAt,
      );

      final map = timer.toMap();
      // Firestore の Timestamp は fake_cloud_firestore を使わない単体テストでは
      // そのまま Map に残るため、DateTime へ変換してから fromMap に渡す形を模す。
      final restored = ActiveTimer.fromMap({
        ...map,
        'startedAtUtc': map['startedAtUtc'],
        'updatedAtUtc': map['updatedAtUtc'],
      });

      expect(restored.taskId, timer.taskId);
      expect(restored.isTodo, timer.isTodo);
      expect(restored.taskTitle, timer.taskTitle);
      expect(restored.predictedMinutes, timer.predictedMinutes);
      // Timestamp.toDate() はローカル時刻を返すため、同一時刻かどうかは
      // isAtSameMomentAs で比較する（UTC/ローカル表記の違いを無視）。
      expect(restored.startedAtUtc!.isAtSameMomentAs(startedAt), isTrue);
      expect(restored.accumulatedSeconds, timer.accumulatedSeconds);
      expect(restored.updatedAtUtc.isAtSameMomentAs(updatedAt), isTrue);
    });

    test('paused な状態（startedAtUtc=null）の往復変換', () {
      final updatedAt = DateTime.utc(2026, 7, 6, 9, 5, 0);
      final timer = ActiveTimer(
        taskId: 'task-456',
        isTodo: false,
        taskTitle: '予定タスク',
        predictedMinutes: 90,
        startedAtUtc: null,
        accumulatedSeconds: 600,
        updatedAtUtc: updatedAt,
      );

      final map = timer.toMap();
      expect(map['startedAtUtc'], isNull);

      final restored = ActiveTimer.fromMap(map);
      expect(restored.startedAtUtc, isNull);
      expect(restored.isRunning, isFalse);
      expect(restored.accumulatedSeconds, 600);
    });

    test('quickStart: toMap/fromMap の往復変換・既定値・copyWith', () {
      final updatedAt = DateTime.utc(2026, 7, 6, 9, 5, 0);
      final timer = ActiveTimer(
        taskId: 'task-789',
        isTodo: false,
        taskTitle: 'クイックスタート',
        predictedMinutes: 0,
        startedAtUtc: null,
        accumulatedSeconds: 0,
        updatedAtUtc: updatedAt,
        quickStart: true,
      );

      final map = timer.toMap();
      expect(map['quickStart'], isTrue);

      final restored = ActiveTimer.fromMap(map);
      expect(restored.quickStart, isTrue);

      // quickStart キーが無い（後方互換）既存docは false にフォールバックする。
      final legacyMap = {...map}..remove('quickStart');
      final legacyRestored = ActiveTimer.fromMap(legacyMap);
      expect(legacyRestored.quickStart, isFalse);

      // 既定値は false。
      expect(
        ActiveTimer(
          taskId: 't',
          isTodo: false,
          taskTitle: 'タスク',
          predictedMinutes: 0,
          startedAtUtc: null,
          accumulatedSeconds: 0,
          updatedAtUtc: updatedAt,
        ).quickStart,
        isFalse,
      );

      // copyWith で明示的に上書きできる。
      final toggledOff = timer.copyWith(quickStart: false);
      expect(toggledOff.quickStart, isFalse);
      // quickStart を渡さなければ元の値を維持する。
      final unchanged = timer.copyWith(taskTitle: '別名');
      expect(unchanged.quickStart, isTrue);
    });
  });
}
