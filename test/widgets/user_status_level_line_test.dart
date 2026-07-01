import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';
import 'package:task_manager/widgets/user_status_panel.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 170, child: child)),
    ),
  );
}

void main() {
  testWidgets('レベル行は Lv.数字 と 称号 を分けて表示する', (tester) async {
    const settings = UserSettings(displayName: 'らいす', cumulativeTaskCount: 10);

    await tester.pumpWidget(_host(UserStatusLevelLine(settings: settings)));
    await tester.pumpAndSettle();

    expect(find.text('Lv.3'), findsOneWidget);
    expect(find.text('駆け出し'), findsOneWidget);
    expect(find.text('レベル'), findsNothing);
    expect(find.text('Lv.3 駆け出し'), findsNothing);
  });
}
