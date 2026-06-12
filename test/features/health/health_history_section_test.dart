import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/health/model/health_log.dart';
import 'package:task_manager/features/health/widgets/health_history_section.dart';

HealthLog _sampleLog({
  required String dateKey,
  required int mealScore,
  required int exerciseScore,
  required int sleepScore,
  required int meditationScore,
  required int totalScore,
  required int provisionalEarnedYen,
  required int finalizedEarnedYen,
  bool isFinalized = false,
}) {
  return HealthLog(
    dateKey: dateKey,
    mealScore: mealScore,
    exerciseScore: exerciseScore,
    sleepScore: sleepScore,
    meditationScore: meditationScore,
    totalScore: totalScore,
    provisionalEarnedYen: provisionalEarnedYen,
    finalizedEarnedYen: finalizedEarnedYen,
    isFinalized: isFinalized,
  );
}

Future<void> _pumpSection(
  WidgetTester tester, {
  required List<HealthLog> logs,
  bool isLoading = false,
  String? errorMessage,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 420,
            child: HealthHistorySection(
              logs: logs,
              isLoading: isLoading,
              errorMessage: errorMessage,
            ),
          ),
        ),
      ),
    ),
  );
  if (isLoading) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  group('HealthHistorySection', () {
    testWidgets('履歴ログが日付・点数・金額つきで表示される', (tester) async {
      final logs = [
        _sampleLog(
          dateKey: '2026-06-10',
          mealScore: 8,
          exerciseScore: 6,
          sleepScore: 9,
          meditationScore: 4,
          totalScore: 71,
          provisionalEarnedYen: 6532,
          finalizedEarnedYen: 6532,
          isFinalized: true,
        ),
      ];

      await _pumpSection(tester, logs: logs);

      expect(find.text('直近14件'), findsOneWidget);
      expect(find.text('6/10'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('71点'), findsOneWidget);
      expect(find.text('¥6,532'), findsOneWidget);
    });

    testWidgets('空リストでは空状態を表示する', (tester) async {
      await _pumpSection(tester, logs: const []);

      expect(find.text('保存済みの履歴がありません'), findsOneWidget);
      expect(find.text('過去に保存したスコアがここに表示されます。'), findsOneWidget);
    });

    testWidgets('読み込み中ではローディング表示になる', (tester) async {
      await _pumpSection(tester, logs: const [], isLoading: true);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('保存済みの履歴がありません'), findsNothing);
    });

    testWidgets('エラー時はカード内にエラー表示を出す', (tester) async {
      await _pumpSection(
        tester,
        logs: const [],
        errorMessage: 'Firestore が応答しませんでした',
      );

      expect(find.text('履歴を読み込めませんでした'), findsOneWidget);
      expect(find.text('Firestore が応答しませんでした'), findsOneWidget);
    });

    testWidgets('確定済みは finalizedEarnedYen、未確定は provisionalEarnedYen を表示する', (
      tester,
    ) async {
      final logs = [
        _sampleLog(
          dateKey: '2026-06-10',
          mealScore: 10,
          exerciseScore: 8,
          sleepScore: 10,
          meditationScore: 8,
          totalScore: 92,
          provisionalEarnedYen: 123456,
          finalizedEarnedYen: 654321,
          isFinalized: true,
        ),
        _sampleLog(
          dateKey: '2026-06-09',
          mealScore: 7,
          exerciseScore: 5,
          sleepScore: 8,
          meditationScore: 5,
          totalScore: 65,
          provisionalEarnedYen: 56789,
          finalizedEarnedYen: 98765,
          isFinalized: false,
        ),
      ];

      await _pumpSection(tester, logs: logs);

      expect(find.text('¥654,321'), findsOneWidget);
      expect(find.text('¥123,456'), findsNothing);
      expect(find.text('¥56,789'), findsOneWidget);
      expect(find.text('¥98,765'), findsNothing);
    });
  });
}
