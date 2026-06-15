import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/widgets/task_detail/quadrant_selector.dart';

void main() {
  group('QuadrantSelector', () {
    testWidgets('2×2配置で4象限の説明が全て描画される', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuadrantSelector(
              selected: Quadrant.urgentImportant,
              onSelect: (_) {},
            ),
          ),
        ),
      );

      // 数字と説明（1行化後も全象限が表示される）
      for (final q in Quadrant.values) {
        expect(find.text('${q.number}'), findsOneWidget);
        expect(find.text(q.adjectives), findsOneWidget);
      }
      // 選択中マスに ✓
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('狭幅（SE級 320px）でもオーバーフローしない', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: QuadrantSelector(
                selected: Quadrant.notUrgentNotImportant,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // RenderFlex overflow があればこの時点で例外が記録されている
      expect(tester.takeException(), isNull);
      // 最長の説明（×緊急・×重要）も省略されず存在
      expect(find.text('×緊急・×重要'), findsOneWidget);
    });

    testWidgets('タップで onSelect が呼ばれる', (tester) async {
      Quadrant? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuadrantSelector(
              selected: Quadrant.urgentImportant,
              onSelect: (q) => picked = q,
            ),
          ),
        ),
      );

      await tester.tap(find.text('×緊急・×重要'));
      await tester.pump();
      expect(picked, Quadrant.notUrgentNotImportant);
    });
  });
}
