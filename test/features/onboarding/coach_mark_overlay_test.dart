import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/onboarding/widgets/coach_mark_overlay.dart';

void main() {
  testWidgets('タップでステップが進み、最終タップで onFinished、「スキップ」で onSkipAll', (tester) async {
    final key1 = GlobalKey();
    final key2 = GlobalKey();
    var finishedCalled = false;
    var skipAllCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 10,
                top: 10,
                child: SizedBox(key: key1, width: 40, height: 40),
              ),
              Positioned(
                left: 100,
                top: 200,
                child: SizedBox(key: key2, width: 40, height: 40),
              ),
              CoachMarkOverlay(
                steps: [
                  CoachMarkStep(targetKey: key1, title: 'ステップ1', body: '本文1'),
                  CoachMarkStep(targetKey: key2, title: 'ステップ2', body: '本文2'),
                ],
                onFinished: () => finishedCalled = true,
                onSkipAll: () => skipAllCalled = true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ステップ1'), findsOneWidget);
    expect(find.text('タップで次へ (1/2)'), findsOneWidget);

    // 黒幕をタップして次へ進める（画面端をタップしてターゲット矩形を避ける）。
    await tester.tapAt(const Offset(300, 500));
    await tester.pumpAndSettle();

    expect(find.text('ステップ2'), findsOneWidget);
    expect(find.text('タップで次へ (2/2)'), findsOneWidget);
    expect(finishedCalled, isFalse);

    // 最終ステップのタップで onFinished。
    await tester.tapAt(const Offset(300, 500));
    await tester.pumpAndSettle();

    expect(finishedCalled, isTrue);
    expect(skipAllCalled, isFalse);
  });

  testWidgets('「スキップ」タップで onSkipAll が呼ばれる', (tester) async {
    final key1 = GlobalKey();
    var skipAllCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 10,
                top: 10,
                child: SizedBox(key: key1, width: 40, height: 40),
              ),
              CoachMarkOverlay(
                steps: [
                  CoachMarkStep(targetKey: key1, title: 'ステップ1', body: '本文1'),
                ],
                onFinished: () {},
                onSkipAll: () => skipAllCalled = true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('スキップ'));
    await tester.pumpAndSettle();

    expect(skipAllCalled, isTrue);
  });

  testWidgets('targetKey が未アタッチのステップでもクラッシュせず吹き出しが中央表示される', (tester) async {
    final unattachedKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              CoachMarkOverlay(
                steps: [
                  CoachMarkStep(targetKey: unattachedKey, title: '不明ステップ', body: '本文'),
                ],
                onFinished: () {},
                onSkipAll: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('不明ステップ'), findsOneWidget);
  });

  testWidgets('targetKey が null のステップでもクラッシュせず吹き出しが中央表示される', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              CoachMarkOverlay(
                steps: const [
                  CoachMarkStep(targetKey: null, title: 'nullステップ', body: '本文'),
                ],
                onFinished: () {},
                onSkipAll: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('nullステップ'), findsOneWidget);
  });
}
