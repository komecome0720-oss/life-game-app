import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/roulette/model/reward_config.dart';
import 'package:task_manager/features/roulette/model/roulette_outcome.dart';
import 'package:task_manager/features/roulette/widgets/roulette_board.dart';
import 'package:task_manager/screens/task_completion_screen.dart';

RouletteProbabilities _probs() => RewardConfig.probabilitiesFor(
  weeklyTaskCount: 56,
  weeklyJackpotCount: 1.5,
  weeklyChuCount: 16.35,
);

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  group('TaskCompletionScreen 演出', () {
    testWidgets('お金は最初から表示される', (tester) async {
      await tester.pumpWidget(
        _host(
          const TaskCompletionScreen(
            taskTitle: 'テスト',
            rewardYen: 1200,
            balanceBeforeYen: 1000,
            balanceAfterYen: 2200,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('獲得金額：¥1,200'), findsOneWidget);
    });

    testWidgets('当たり: 完了後に待機してからスピンし、ご褒美名が表示される', (tester) async {
      await tester.pumpWidget(
        _host(
          TaskCompletionScreen(
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
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(RouletteBoard), findsOneWidget);
      expect(find.text('ご褒美ルーレットを抽選します'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('抽選中...'), findsOneWidget);
      expect(find.text('タップでスキップ'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 4100));
      await tester.pump();
      expect(find.text('中当たり！'), findsOneWidget);
      expect(find.textContaining('ドラマ1話'), findsWidgets);
      // メニュー誘導の注記
      expect(find.textContaining('メニュー画面から変更できます'), findsOneWidget);
    });

    testWidgets('スピン中にタップすると即座に結果表示に切り替わる', (tester) async {
      await tester.pumpWidget(
        _host(
          TaskCompletionScreen(
            taskTitle: 'テスト',
            rewardYen: 500,
            outcome: RouletteOutcome.win(
              probabilities: _probs(),
              landedCategory: RouletteCategory.chu,
              tier: RouletteCategory.chu,
              rewardName: 'ドラマ1話',
              banked: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.byType(RouletteBoard));
      await tester.pump();
      expect(find.text('中当たり！'), findsOneWidget);
    });

    testWidgets('小当たりは即時許可の文言（チケットではない）', (tester) async {
      await tester.pumpWidget(
        _host(
          TaskCompletionScreen(
            taskTitle: 'テスト',
            rewardYen: 500,
            outcome: RouletteOutcome.win(
              probabilities: _probs(),
              landedCategory: RouletteCategory.sho,
              tier: RouletteCategory.sho,
              rewardName: '好きな飲み物で休憩',
              banked: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 4100));
      await tester.pump();
      expect(find.textContaining('今すぐ'), findsOneWidget);
      expect(find.textContaining('好きな飲み物で休憩'), findsWidgets);
    });

    testWidgets('ハズレはご褒美なしの文言で表示する', (tester) async {
      await tester.pumpWidget(
        _host(
          TaskCompletionScreen(
            taskTitle: 'テスト',
            rewardYen: 500,
            outcome: RouletteOutcome.nearMiss(probabilities: _probs()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 4100));
      await tester.pump();
      expect(find.text('ハズレ'), findsOneWidget);
      expect(find.textContaining('今回はご褒美なし'), findsOneWidget);
    });

    testWidgets('レベルアップ時は称賛バナーが出る', (tester) async {
      // C(2)=3 を跨ぐ: 2 → 3 で Lv1→Lv2
      await tester.pumpWidget(
        _host(
          TaskCompletionScreen(
            taskTitle: 'テスト',
            rewardYen: 500,
            cumulativeTaskCountBefore: 2,
            cumulativeTaskCountAfter: 3,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.textContaining('レベルアップ！ Lv.2'), findsOneWidget);
      expect(find.textContaining('次のレベルまであと'), findsOneWidget);
    });

    testWidgets('outcome なしなら盤面は出ない', (tester) async {
      await tester.pumpWidget(
        _host(const TaskCompletionScreen(taskTitle: 'テスト', rewardYen: 500)),
      );
      await tester.pump();
      expect(find.byType(RouletteBoard), findsNothing);
    });
  });
}
