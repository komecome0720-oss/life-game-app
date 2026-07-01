import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/widgets/quick_create_sheet.dart';

Future<void> _pumpHarness(
  WidgetTester tester, {
  required ValueChanged<QuickCreateResult?> onResult,
  DateTime? initialStart,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              final result = await showModalBottomSheet<QuickCreateResult>(
                context: context,
                isScrollControlled: true,
                builder: (_) => QuickCreateSheet(
                  initialStart: initialStart ?? DateTime(2026, 6, 23, 20, 15),
                ),
              );
              onResult(result);
            },
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
  setUpAll(() async {
    await initializeDateFormatting('ja_JP');
  });

  group('QuickCreateSheet', () {
    testWidgets('タイトルと日時の間に領域セレクターを表示する', (tester) async {
      await _pumpHarness(tester, onResult: (_) {});

      expect(find.text('予定を追加'), findsOneWidget);
      expect(find.text('領域'), findsOneWidget);
      for (final q in Quadrant.values) {
        expect(find.text('${q.number}'), findsOneWidget);
        expect(find.text(q.adjectives), findsOneWidget);
      }

      final titleBottom = tester.getBottomLeft(find.byType(TextField)).dy;
      final quadrantTop = tester.getTopLeft(find.text('領域')).dy;
      final timeTop = tester.getTopLeft(find.text('6月23日 (火) 20:15')).dy;
      expect(quadrantTop, greaterThan(titleBottom));
      expect(timeTop, greaterThan(quadrantTop));
    });

    testWidgets('初期選択は第1領域で、保存結果に含まれる', (tester) async {
      QuickCreateResult? captured;
      await _pumpHarness(tester, onResult: (result) => captured = result);

      await tester.enterText(find.byType(TextField), '打ち合わせ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(captured?.title, '打ち合わせ');
      expect(captured?.durationMinutes, 60);
      expect(captured?.quadrant, Quadrant.urgentImportant);
    });

    testWidgets('選択した領域が保存結果に含まれる', (tester) async {
      QuickCreateResult? captured;
      await _pumpHarness(tester, onResult: (result) => captured = result);

      await tester.enterText(find.byType(TextField), '資料整理');
      await tester.tap(find.text('×緊急・×重要'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(captured?.quadrant, Quadrant.notUrgentNotImportant);
    });

    testWidgets('空タイトルでは保存しても閉じない', (tester) async {
      QuickCreateResult? captured;
      await _pumpHarness(tester, onResult: (result) => captured = result);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(captured, isNull);
      expect(find.text('予定を追加'), findsOneWidget);
    });

    testWidgets('狭幅かつキーボード表示相当でもオーバーフローしない', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);

      await _pumpHarness(tester, onResult: (_) {});
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('領域'), findsOneWidget);
    });
  });
}
