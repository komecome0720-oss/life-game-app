import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/timer/model/task_sheet_result.dart';
import 'package:task_manager/features/timer/widgets/split_start_button.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/widgets/task_event_detail_sheet.dart';

// 実績分フィールドを特定するキーを再エクスポート
const _actualKey = kActualMinutesFieldKey;

CalendarTask _sampleTask({bool isCompleted = false}) {
  final start = DateTime(2026, 5, 6, 9, 0);
  final end = start.add(const Duration(minutes: 60));
  return CalendarTask(
    id: 't1',
    title: 'テストタスク',
    start: start,
    end: end,
    rewardYen: 300,
    isCompleted: isCompleted,
  );
}

/// シートを開くだけの簡易ハーネス。
Future<void> _pumpSheet(
  WidgetTester tester, {
  required CalendarTask task,
  required int predictedMinutes,
  required int expectedRewardYen,
  required TaskCompleteCallback onComplete,
  TaskSaveEditsCallback? onSaveEdits,
  ValueChanged<TaskSheetResult?>? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showTaskEventDetailSheet(
              context: ctx,
              task: task,
              predictedMinutes: predictedMinutes,
              expectedRewardYen: expectedRewardYen,
              onComplete: onComplete,
              onSaveEdits: onSaveEdits,
            ).then((r) => onResult?.call(r)),
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

void main() {
  group('task_event_detail_sheet', () {
    testWidgets('見込時間と期待報酬が表示される', (tester) async {
      await _pumpSheet(
        tester,
        task: _sampleTask(),
        predictedMinutes: 60,
        expectedRewardYen: 1500,
        onComplete: ({required predictedMinutes, required actualMinutes}) async {},
      );

      expect(find.text('見込時間：60分'), findsOneWidget);
      expect(find.text('¥1,500'), findsOneWidget);
      expect(find.text('現状'), findsOneWidget);
    });

    testWidgets('見込時間 0 かつ start/end なしのとき "—" を表示', (tester) async {
      // start/end のないタスク（ToDo相当）: _livePredictedMinutes が widget.predictedMinutes=0 にフォールバック
      const taskWithoutTimes = CalendarTask(
        id: 't2',
        title: 'noTimeTask',
        start: null,
        end: null,
        rewardYen: 0,
      );
      await _pumpSheet(
        tester,
        task: taskWithoutTimes,
        predictedMinutes: 0,
        expectedRewardYen: 0,
        onComplete: ({required predictedMinutes, required actualMinutes}) async {},
      );

      expect(find.text('見込時間：—'), findsOneWidget);
    });

    testWidgets('テキストフィールドに数値を入れて完了するとその値が actualMinutes',
        (tester) async {
      int? capturedActual;
      int? capturedPredicted;
      await _pumpSheet(
        tester,
        task: _sampleTask(),
        predictedMinutes: 60,
        expectedRewardYen: 1500,
        onComplete: ({required predictedMinutes, required actualMinutes}) async {
          capturedPredicted = predictedMinutes;
          capturedActual = actualMinutes;
        },
      );

      // 実績分フィールドに 45 を入力（Key で特定）
      await tester.enterText(find.byKey(_actualKey), '45');
      await tester.pump();
      // 完了ボタン（SingleChildScrollView 内にある可能性があるため ensureVisible）
      await tester.ensureVisible(find.text('完了'));
      await tester.tap(find.text('完了'));
      await tester.pumpAndSettle();

      expect(capturedActual, 45);
      expect(capturedPredicted, 60);
    });

    testWidgets('タイマー・フィールドともに空で完了するとダイアログが出る', (tester) async {
      bool called = false;
      await _pumpSheet(
        tester,
        task: _sampleTask(),
        predictedMinutes: 60,
        expectedRewardYen: 1500,
        onComplete: ({required predictedMinutes, required actualMinutes}) async {
          called = true;
        },
      );

      await tester.ensureVisible(find.text('完了'));
      await tester.tap(find.text('完了'));
      await tester.pumpAndSettle();

      expect(find.text('時間ログなしで完了しますか？'), findsOneWidget);
      expect(find.text('時間予測ログが残りませんがよろしいですか？'), findsOneWidget);
      expect(called, isFalse);
    });

    testWidgets('ダイアログ「いいえ」で完了せず戻る', (tester) async {
      bool called = false;
      await _pumpSheet(
        tester,
        task: _sampleTask(),
        predictedMinutes: 60,
        expectedRewardYen: 1500,
        onComplete: ({required predictedMinutes, required actualMinutes}) async {
          called = true;
        },
      );

      await tester.ensureVisible(find.text('完了'));
      await tester.tap(find.text('完了'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('いいえ'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
    });

    testWidgets('ダイアログ「はい」で actualMinutes=null として完了する', (tester) async {
      int? capturedActual = -1; // sentinel
      int? capturedPredicted;
      await _pumpSheet(
        tester,
        task: _sampleTask(),
        predictedMinutes: 60,
        expectedRewardYen: 1500,
        onComplete: ({required predictedMinutes, required actualMinutes}) async {
          capturedActual = actualMinutes;
          capturedPredicted = predictedMinutes;
        },
      );

      await tester.ensureVisible(find.text('完了'));
      await tester.tap(find.text('完了'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('はい'));
      await tester.pumpAndSettle();

      expect(capturedActual, isNull);
      expect(capturedPredicted, 60);
    });

    testWidgets('保存ボタンで onSaveEdits が呼ばれ、成功でシートが閉じる', (tester) async {
      int callCount = 0;
      int? savedActual;
      await _pumpSheet(
        tester,
        task: _sampleTask(),
        predictedMinutes: 60,
        expectedRewardYen: 1500,
        onComplete: ({required predictedMinutes, required actualMinutes}) async {},
        onSaveEdits: ({
          required title,
          required quadrant,
          required start,
          required end,
          required predictedMinutes,
          required actualMinutes,
        }) async {
          callCount++;
          savedActual = actualMinutes;
          return true;
        },
      );

      // 実績分を入力して保存
      await tester.enterText(find.byKey(_actualKey), '42');
      await tester.pump();
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // onSaveEdits は1回だけ・実績分が渡る・シートは閉じる（保存ボタンが消える）
      expect(callCount, 1);
      expect(savedActual, 42);
      expect(find.text('保存'), findsNothing);
    });

    testWidgets('保存に失敗するとシートは閉じない', (tester) async {
      await _pumpSheet(
        tester,
        task: _sampleTask(),
        predictedMinutes: 60,
        expectedRewardYen: 1500,
        onComplete: ({required predictedMinutes, required actualMinutes}) async {},
        onSaveEdits: ({
          required title,
          required quadrant,
          required start,
          required end,
          required predictedMinutes,
          required actualMinutes,
        }) async {
          return false; // 保存失敗
        },
      );

      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 失敗時はシートが開いたまま（保存ボタンが残る）
      expect(find.text('保存'), findsOneWidget);
    });

    testWidgets('未編集なら本文の下フリックでシートが閉じる', (tester) async {
      await _pumpSheet(
        tester,
        task: _sampleTask(),
        predictedMinutes: 60,
        expectedRewardYen: 1500,
        onComplete: ({required predictedMinutes, required actualMinutes}) async {},
      );
      expect(find.text('見込時間：60分'), findsOneWidget);

      // スクロール最上部の状態で本文を下方向へフリック → シートごと閉じる
      await tester.fling(
        find.text('見込時間：60分'),
        const Offset(0, 600),
        2000,
      );
      await tester.pumpAndSettle();

      expect(find.text('見込時間：60分'), findsNothing);
    });

    testWidgets('編集中に下フリックすると確認ダイアログが出て「破棄」で閉じる', (tester) async {
      await _pumpSheet(
        tester,
        task: _sampleTask(),
        predictedMinutes: 60,
        expectedRewardYen: 1500,
        onComplete: ({required predictedMinutes, required actualMinutes}) async {},
      );

      // タイトルを書き換えてダーティにする
      await tester.enterText(
        find.widgetWithText(TextField, 'テストタスク'),
        '編集後タイトル',
      );
      await tester.pump();

      await tester.fling(
        find.text('見込時間：60分'),
        const Offset(0, 600),
        2000,
      );
      await tester.pumpAndSettle();

      // 未保存ガードのダイアログが出て、シートは閉じない
      expect(find.text('変更を保存しますか？'), findsOneWidget);
      expect(find.text('見込時間：60分'), findsOneWidget);

      await tester.tap(find.text('破棄'));
      await tester.pumpAndSettle();

      expect(find.text('見込時間：60分'), findsNothing);
    });

    testWidgets('スタートボタンでシートが閉じ、startTimer が返る', (tester) async {
      TaskSheetResult? result;
      await _pumpSheet(
        tester,
        task: _sampleTask(),
        predictedMinutes: 60,
        expectedRewardYen: 1500,
        onComplete: ({required predictedMinutes, required actualMinutes}) async {},
        onResult: (r) => result = r,
      );

      await tester.ensureVisible(find.byKey(kSplitStartButtonStartKey));
      await tester.tap(find.byKey(kSplitStartButtonStartKey));
      await tester.pumpAndSettle();

      expect(result, TaskSheetResult.startTimer);
      expect(find.text('見込時間：60分'), findsNothing);
    });

    testWidgets('ポモドーロボタンでシートが閉じ、startPomodoro が返る', (tester) async {
      TaskSheetResult? result;
      await _pumpSheet(
        tester,
        task: _sampleTask(),
        predictedMinutes: 60,
        expectedRewardYen: 1500,
        onComplete: ({required predictedMinutes, required actualMinutes}) async {},
        onResult: (r) => result = r,
      );

      await tester.ensureVisible(find.byKey(kSplitStartButtonPomodoroKey));
      await tester.tap(find.byKey(kSplitStartButtonPomodoroKey));
      await tester.pumpAndSettle();

      expect(result, TaskSheetResult.startPomodoro);
      expect(find.text('見込時間：60分'), findsNothing);
    });
  });
}
