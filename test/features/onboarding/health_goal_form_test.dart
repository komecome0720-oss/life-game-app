import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/onboarding/widgets/health_goal_form.dart';

Widget _host(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

const _allZeroInitial = HealthGoalFormInitial(
  mealGoalGrams: 0,
  exerciseGoalMinutes: 0,
  sleepGoalHours: 0,
  sleepGoalMinutesExtra: 0,
  meditationGoalMinutes: 0,
);

void main() {
  testWidgets('initial 全0ならプリセット値（350/20/7/0/10）が表示される', (tester) async {
    await tester.pumpWidget(
      _host(
        HealthGoalForm(
          initial: _allZeroInitial,
          onSubmit: (_, _, _, _, _) {},
          onSkip: () {},
        ),
      ),
    );

    expect(find.text('350'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
  });

  testWidgets('既存値（運動45分）がある場合はその値が表示され、0の項目のみプリセットされる', (tester) async {
    await tester.pumpWidget(
      _host(
        HealthGoalForm(
          initial: const HealthGoalFormInitial(
            mealGoalGrams: 0,
            exerciseGoalMinutes: 45,
            sleepGoalHours: 0,
            sleepGoalMinutesExtra: 0,
            meditationGoalMinutes: 0,
          ),
          onSubmit: (_, _, _, _, _) {},
          onSkip: () {},
        ),
      ),
    );

    expect(find.text('45'), findsOneWidget);
    // 他の項目はプリセット値のまま
    expect(find.text('350'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
  });

  testWidgets('「この目標で始める」をタップすると onSubmit に入力値が渡る', (tester) async {
    int? meal, exercise, sleepH, sleepM, meditation;
    await tester.pumpWidget(
      _host(
        HealthGoalForm(
          initial: _allZeroInitial,
          onSubmit: (m, e, sh, sm, med) {
            meal = m;
            exercise = e;
            sleepH = sh;
            sleepM = sm;
            meditation = med;
          },
          onSkip: () {},
        ),
      ),
    );

    await tester.tap(find.text('この目標で始める'));
    await tester.pumpAndSettle();

    expect(meal, 350);
    expect(exercise, 20);
    expect(sleepH, 7);
    expect(sleepM, 0);
    expect(meditation, 10);
  });

  testWidgets('「あとで設定」をタップすると onSkip が呼ばれる', (tester) async {
    var skipped = false;
    await tester.pumpWidget(
      _host(
        HealthGoalForm(
          initial: _allZeroInitial,
          onSubmit: (_, _, _, _, _) {},
          onSkip: () => skipped = true,
        ),
      ),
    );

    await tester.tap(find.text('あとで設定'));
    await tester.pumpAndSettle();

    expect(skipped, isTrue);
  });
}
