import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/wish_list/view/wish_item_completion_screen.dart';

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  group('WishItemCompletionScreen', () {
    testWidgets('shopUrl 空 → 「ショップを見る」ボタンなし', (tester) async {
      await tester.pumpWidget(
        _host(
          const WishItemCompletionScreen(
            userName: 'テスト',
            itemPrice: 1000,
            balanceBeforeYen: 500,
            balanceAfterYen: 1500,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('ショップを見る'), findsNothing);
    });

    testWidgets('shopUrl あり → ボタンあり', (tester) async {
      await tester.pumpWidget(
        _host(
          const WishItemCompletionScreen(
            userName: 'テスト',
            itemPrice: 1000,
            balanceBeforeYen: 500,
            balanceAfterYen: 1500,
            shopUrl: 'https://example.com/item',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('ショップを見る'), findsOneWidget);
    });
  });
}
