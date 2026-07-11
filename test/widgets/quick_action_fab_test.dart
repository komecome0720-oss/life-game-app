import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/widgets/quick_action_fab.dart';

void main() {
  group('QuickActionFab', () {
    Widget buildApp({
      required VoidCallback onTap,
      required VoidCallback onTriggerFirst,
      required VoidCallback onTriggerSecond,
    }) {
      return MaterialApp(
        home: Scaffold(
          floatingActionButton: QuickActionFab(
            heroTag: 'test_fab',
            icon: Icons.add,
            onTap: onTap,
            actions: [
              QuickAction(
                icon: Icons.timer_outlined,
                label: 'ストップウォッチ',
                tooltip: 'ストップウォッチ',
                onTrigger: onTriggerFirst,
              ),
              QuickAction(
                icon: Icons.local_cafe_outlined,
                label: 'ポモドーロ',
                tooltip: 'ポモドーロ',
                onTrigger: onTriggerSecond,
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('長押し開始でオーバーレイに2ボタン＋2ラベルが出る', (tester) async {
      await tester.pumpWidget(
        buildApp(onTap: () {}, onTriggerFirst: () {}, onTriggerSecond: () {}),
      );

      final fabCenter = tester.getCenter(find.byType(FloatingActionButton));
      final gesture = await tester.startGesture(fabCenter);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

      // FAB本体 + 2つのオーバーレイボタン = 3
      expect(find.byType(FloatingActionButton), findsNWidgets(3));
      expect(find.text('ストップウォッチ'), findsOneWidget);
      expect(find.text('ポモドーロ'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('対象ボタン位置でリリースするとonTriggerが呼ばれる', (tester) async {
      var firstTriggered = false;
      var secondTriggered = false;
      await tester.pumpWidget(
        buildApp(
          onTap: () {},
          onTriggerFirst: () => firstTriggered = true,
          onTriggerSecond: () => secondTriggered = true,
        ),
      );

      final fabCenter = tester.getCenter(find.byType(FloatingActionButton));
      final gesture = await tester.startGesture(fabCenter);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

      // index0（ストップウォッチ）はFABに最も近い＝1段上。
      final firstButtonOffset = fabCenter - const Offset(0, 56 + 16);
      await gesture.moveTo(firstButtonOffset);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(firstTriggered, isTrue);
      expect(secondTriggered, isFalse);
    });

    testWidgets('対象外の位置でリリースするとどちらのonTriggerも呼ばれない', (tester) async {
      var firstTriggered = false;
      var secondTriggered = false;
      await tester.pumpWidget(
        buildApp(
          onTap: () {},
          onTriggerFirst: () => firstTriggered = true,
          onTriggerSecond: () => secondTriggered = true,
        ),
      );

      final fabCenter = tester.getCenter(find.byType(FloatingActionButton));
      final gesture = await tester.startGesture(fabCenter);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

      // ボタンからは大きく外れた位置（画面左上寄り）でリリース。
      await gesture.moveTo(const Offset(10, 10));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(firstTriggered, isFalse);
      expect(secondTriggered, isFalse);
    });

    testWidgets('短タップではonTapが呼ばれる', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        buildApp(
          onTap: () => tapped = true,
          onTriggerFirst: () {},
          onTriggerSecond: () {},
        ),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });
  });
}
