import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/roulette/model/reward_config.dart';
import 'package:task_manager/features/roulette/model/roulette_outcome.dart';
import 'package:task_manager/features/roulette/widgets/roulette_board.dart';
import 'package:task_manager/screens/task_completion_screen.dart';

RouletteProbabilities _probs() => RewardConfig.probabilitiesFor(
      weeklyTaskCount: 56,
      weeklyJackpotCount: 1.5,
    );

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  group('TaskCompletionScreen 演出', () {
    testWidgets('お金は最初から表示される', (tester) async {
      await tester.pumpWidget(_host(const TaskCompletionScreen(
        taskTitle: 'テスト',
        rewardYen: 1200,
        balanceBeforeYen: 1000,
        balanceAfterYen: 2200,
      )));
      await tester.pump();
      expect(find.text('獲得金額：¥1,200'), findsOneWidget);
    });

    testWidgets('当たり: 盤面が出てスピン後にご褒美名が表示される', (tester) async {
      await tester.pumpWidget(_host(TaskCompletionScreen(
        taskTitle: 'テスト',
        rewardYen: 500,
        outcome: RouletteOutcome.win(
          probabilities: _probs(),
          landedCategory: RouletteCategory.chu,
          tier: RouletteCategory.chu,
          rewardName: 'ドラマ1話',
          banked: true,
        ),
        cumulativeTaskCountBefore: 5,
        cumulativeTaskCountAfter: 6,
      )));
      await tester.pump(); // postFrame で spin 開始
      expect(find.byType(RouletteBoard), findsOneWidget);
      // スピン完了まで進める
      await tester.pumpAndSettle();
      expect(find.text('中当たり！'), findsOneWidget);
      expect(find.textContaining('ドラマ1話'), findsWidgets);
      // メニュー誘導の注記
      expect(find.textContaining('メニュー画面から変更できます'), findsOneWidget);
    });

    testWidgets('小当たりは即時許可の文言（チケットではない）', (tester) async {
      await tester.pumpWidget(_host(TaskCompletionScreen(
        taskTitle: 'テスト',
        rewardYen: 500,
        outcome: RouletteOutcome.win(
          probabilities: _probs(),
          landedCategory: RouletteCategory.sho,
          tier: RouletteCategory.sho,
          rewardName: '好きな飲み物で休憩',
          banked: false,
        ),
      )));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.textContaining('今すぐ'), findsOneWidget);
      expect(find.textContaining('好きな飲み物で休憩'), findsWidgets);
    });

    testWidgets('ハズレはニアミス表現で罰に見せない', (tester) async {
      await tester.pumpWidget(_host(TaskCompletionScreen(
        taskTitle: 'テスト',
        rewardYen: 500,
        outcome: RouletteOutcome.nearMiss(probabilities: _probs()),
      )));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('もう少し！'), findsOneWidget);
      expect(find.textContaining('お金はしっかり獲得'), findsOneWidget);
    });

    testWidgets('レベルアップ時は称賛バナーが出る', (tester) async {
      // C(2)=3 を跨ぐ: 2 → 3 で Lv1→Lv2
      await tester.pumpWidget(_host(TaskCompletionScreen(
        taskTitle: 'テスト',
        rewardYen: 500,
        cumulativeTaskCountBefore: 2,
        cumulativeTaskCountAfter: 3,
      )));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.textContaining('レベルアップ！ Lv.2'), findsOneWidget);
      expect(find.textContaining('次のレベルまであと'), findsOneWidget);
    });

    testWidgets('outcome なしなら盤面は出ない', (tester) async {
      await tester.pumpWidget(_host(const TaskCompletionScreen(
        taskTitle: 'テスト',
        rewardYen: 500,
      )));
      await tester.pump();
      expect(find.byType(RouletteBoard), findsNothing);
    });
  });
}
