import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/onboarding/widgets/status_form.dart';

Widget _host(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

const _emptyInitial = StatusFormInitial(
  displayName: '',
  monthlyBudget: 0,
  monthlyQuestDays: 0,
  dailyQuestMinutes: 0,
);

void main() {
  testWidgets('空欄で「次へ」をタップするとバリデーションエラーが出て onSubmit は呼ばれない', (tester) async {
    var called = false;
    await tester.pumpWidget(
      _host(
        StatusForm(
          initial: _emptyInitial,
          onSubmit: (_, _, _, _) => called = true,
        ),
      ),
    );

    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('名前を入力してください'), findsOneWidget);
  });

  testWidgets('予算30000・日数20・時間60を入力すると時間単価1,500円/時間が表示される', (tester) async {
    await tester.pumpWidget(
      _host(
        StatusForm(
          initial: _emptyInitial,
          onSubmit: (_, _, _, _) {},
        ),
      ),
    );

    await tester.enterText(find.widgetWithText(TextFormField, '① 月に使えるお金'), '30000');
    await tester.enterText(find.widgetWithText(TextFormField, '② 月のクエスト日数'), '20');
    await tester.enterText(find.widgetWithText(TextFormField, '③ 1日の想定クエスト時間'), '60');
    await tester.pumpAndSettle();

    expect(find.textContaining('1,500'), findsOneWidget);
  });

  testWidgets('正しい入力で onSubmit が正しい値で呼ばれる', (tester) async {
    String? name;
    int? budget;
    int? days;
    int? minutes;
    await tester.pumpWidget(
      _host(
        StatusForm(
          initial: _emptyInitial,
          onSubmit: (n, b, d, m) {
            name = n;
            budget = b;
            days = d;
            minutes = m;
          },
        ),
      ),
    );

    await tester.enterText(find.widgetWithText(TextFormField, '名前'), 'たろう');
    await tester.enterText(find.widgetWithText(TextFormField, '① 月に使えるお金'), '30000');
    await tester.enterText(find.widgetWithText(TextFormField, '② 月のクエスト日数'), '20');
    await tester.enterText(find.widgetWithText(TextFormField, '③ 1日の想定クエスト時間'), '60');
    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();

    expect(name, 'たろう');
    expect(budget, 30000);
    expect(days, 20);
    expect(minutes, 60);
  });

  testWidgets('initial に既存値を渡すとプリフィルされる', (tester) async {
    await tester.pumpWidget(
      _host(
        StatusForm(
          initial: const StatusFormInitial(
            displayName: 'はなこ',
            monthlyBudget: 50000,
            monthlyQuestDays: 22,
            dailyQuestMinutes: 90,
          ),
          onSubmit: (_, _, _, _) {},
        ),
      ),
    );

    expect(find.text('はなこ'), findsOneWidget);
    expect(find.text('50000'), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);
  });
}
