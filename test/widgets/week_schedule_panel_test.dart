import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/widgets/week_schedule_panel.dart';

Widget _buildPanel({List<CalendarTask> tasks = const []}) {
  final day = DateTime(2026, 7, 5);
  return MaterialApp(
    home: Scaffold(
      body: WeekSchedulePanel(
        visibleDays: [day],
        tasks: tasks,
        onTaskTap: (_) {},
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja_JP');
  });

  testWidgets('9:00ラベルの中心が罫線位置(9 * hourHeight)と一致する', (tester) async {
    await tester.pumpWidget(
      ProviderScope(child: _buildPanel()),
    );
    await tester.pump();

    final labelFinder = find.text('9:00');
    expect(labelFinder, findsOneWidget);

    final scrollViewFinder = find.byType(SingleChildScrollView);
    final scrollTop = tester.getTopLeft(scrollViewFinder).dy;
    final labelCenter = tester.getCenter(labelFinder).dy;
    final scrollable = tester.widget<SingleChildScrollView>(scrollViewFinder);
    final scrollOffset = scrollable.controller!.offset;

    const hourHeight = 48.0;
    final expectedCenter = scrollTop - scrollOffset + 9 * hourHeight;

    expect((labelCenter - expectedCenter).abs(), lessThan(1.5));
  });

  testWidgets('初回マウント後、スクロール位置が0以上maxScrollExtent以下になっている', (tester) async {
    await tester.pumpWidget(
      ProviderScope(child: _buildPanel()),
    );
    await tester.pump();

    final scrollViewFinder = find.byType(SingleChildScrollView);
    final scrollable = tester.widget<SingleChildScrollView>(scrollViewFinder);
    final controller = scrollable.controller;
    expect(controller, isNotNull);
    expect(controller!.hasClients, isTrue);
    expect(controller.offset, greaterThanOrEqualTo(0));
    expect(controller.offset,
        lessThanOrEqualTo(controller.position.maxScrollExtent));
  });

  testWidgets('calendarHourHeightProviderをoverrideすると1時間の高さが反映される',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          calendarHourHeightProvider.overrideWith(
            () => _FixedHourHeightNotifier(96.0),
          ),
        ],
        child: _buildPanel(),
      ),
    );
    await tester.pump();

    final label1 = find.text('1:00');
    final label2 = find.text('2:00');
    expect(label1, findsOneWidget);
    expect(label2, findsOneWidget);

    final y1 = tester.getCenter(label1).dy;
    final y2 = tester.getCenter(label2).dy;

    expect((y2 - y1).abs(), closeTo(96.0, 1.5));
  });

  testWidgets('終了時刻が日をまたぐ予定も消えずに描画される', (tester) async {
    // 23:15開始・翌日00:15終了（デフォルト60分の予定を23:15に作成したケースを再現）。
    final task = CalendarTask(
      id: 'task-b',
      title: '日またぎ予定',
      start: DateTime(2026, 7, 5, 23, 15),
      end: DateTime(2026, 7, 6, 0, 15),
      rewardYen: 0,
    );
    await tester.pumpWidget(
      ProviderScope(child: _buildPanel(tasks: [task])),
    );
    await tester.pump();

    expect(find.text('日またぎ予定'), findsOneWidget);
  });

  testWidgets('日をまたぐ予定と重ならない同日予定は通常通りフル幅で描画される', (tester) async {
    // 22:45開始・23:45終了（同日完結）の予定は、日またぎ予定が存在しなければ
    // レーン分割されずフル幅で表示される。
    final task = CalendarTask(
      id: 'task-a',
      title: '同日予定',
      start: DateTime(2026, 7, 5, 22, 45),
      end: DateTime(2026, 7, 5, 23, 45),
      rewardYen: 0,
    );
    await tester.pumpWidget(
      ProviderScope(child: _buildPanel(tasks: [task])),
    );
    await tester.pump();

    expect(find.text('同日予定'), findsOneWidget);
  });
}

class _FixedHourHeightNotifier extends CalendarHourHeightNotifier {
  _FixedHourHeightNotifier(this._initial);
  final double _initial;

  @override
  double build() => _initial;
}
