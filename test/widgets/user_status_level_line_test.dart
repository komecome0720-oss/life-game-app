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
  testWidgets('レベル行は称号を表示せず、Lv.数字の行に「次まであと」を表示する', (tester) async {
    const settings = UserSettings(displayName: 'らいす', cumulativeTaskCount: 10);

    await tester.pumpWidget(_host(UserStatusLevelLine(settings: settings)));
    await tester.pumpAndSettle();

    expect(find.text('Lv.3'), findsOneWidget);
    expect(find.text('駆け出し'), findsNothing);
    expect(find.text('レベル'), findsNothing);
    expect(find.text('Lv.3 駆け出し'), findsNothing);
    expect(find.textContaining('次まであと'), findsOneWidget);
  });
}
