import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/adventure_log/model/daily_earning.dart';
import 'package:task_manager/features/adventure_log/widgets/cumulative_earnings_chart.dart';

void main() {
  group('chartRectFor', () {
    test('week表示はラベル分のtopが広い', () {
      const size = Size(300, 200);
      final weekRect = chartRectFor(size, EarningsPeriod.week);
      final monthRect = chartRectFor(size, EarningsPeriod.month);

      expect(weekRect.top, 22.0);
      expect(monthRect.top, 8.0);
      expect(weekRect.top, greaterThan(monthRect.top));
    });

    test('left/right/bottomはperiodによらず一定', () {
      const size = Size(300, 200);
      final weekRect = chartRectFor(size, EarningsPeriod.week);
      final yearRect = chartRectFor(size, EarningsPeriod.year);

      expect(weekRect.left, yearRect.left);
      expect(weekRect.right, yearRect.right);
      expect(weekRect.bottom, yearRect.bottom);
    });
  });

  group('nearestPointIndex', () {
    test('pointCountが1以下なら常に0', () {
      final chart = Rect.fromLTWH(0, 0, 100, 100);
      expect(nearestPointIndex(50, chart, 1), 0);
      expect(nearestPointIndex(0, chart, 0), 0);
    });

    test('中央の座標は中間のインデックスにスナップする', () {
      final chart = Rect.fromLTWH(0, 0, 100, 100);
      // 11点 (index 0..10)。中央 dx=50 は index 5 に最も近い。
      expect(nearestPointIndex(50, chart, 11), 5);
    });

    test('左端はindex 0、右端は最後のindexにスナップする', () {
      final chart = Rect.fromLTWH(0, 0, 100, 100);
      expect(nearestPointIndex(0, chart, 11), 0);
      expect(nearestPointIndex(100, chart, 11), 10);
    });

    test('範囲外の座標はclampされる', () {
      final chart = Rect.fromLTWH(10, 0, 100, 100);
      expect(nearestPointIndex(-1000, chart, 11), 0);
      expect(nearestPointIndex(1000, chart, 11), 10);
    });

    test('chart.leftがオフセットされていても正しく計算される', () {
      final chart = Rect.fromLTWH(46, 0, 100, 100);
      expect(nearestPointIndex(46, chart, 5), 0);
      expect(nearestPointIndex(146, chart, 5), 4);
    });
  });

  group('axisLabelIndices', () {
    test('0件なら空', () {
      expect(axisLabelIndices(0), isEmpty);
    });

    test('7件以下ならすべてのインデックスを返す', () {
      expect(axisLabelIndices(1), [0]);
      expect(axisLabelIndices(7), [0, 1, 2, 3, 4, 5, 6]);
    });

    test('7件より多い場合は7件を均等にサンプリングする', () {
      final indices = axisLabelIndices(30);
      expect(indices.length, 7);
      expect(indices.first, 0);
      expect(indices.last, 29);
    });

    test('365件（年表示）でも7件均等にサンプリングされ範囲内に収まる', () {
      final indices = axisLabelIndices(365);
      expect(indices.length, 7);
      expect(indices.first, 0);
      expect(indices.last, 364);
      for (final i in indices) {
        expect(i, inInclusiveRange(0, 364));
      }
    });
  });

  group('CumulativeEarningsChart widget smoke test', () {
    Widget buildTestWidget(EarningsWindowData data) {
      return MaterialApp(
        home: Scaffold(
          body: CumulativeEarningsChart(data: data, height: 200),
        ),
      );
    }

    EarningsWindowData makeData({
      required EarningsPeriod period,
      required int pointCount,
    }) {
      final points = List.generate(
        pointCount,
        (i) => CumulativePoint(
          DateTime(2026, 1, 1).add(Duration(days: i)),
          1000 * (i + 1),
        ),
      );
      return EarningsWindowData(
        cumulativePoints: points,
        totalYen: pointCount > 0 ? points.last.cumulativeYen : 0,
        bars: const [],
        period: period,
      );
    }

    testWidgets('week期間はGestureDetectorを持たない', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(makeData(period: EarningsPeriod.week, pointCount: 7)),
      );
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('month期間はGestureDetectorを持つ', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          makeData(period: EarningsPeriod.month, pointCount: 30),
        ),
      );
      expect(find.byType(GestureDetector), findsOneWidget);
    });

    for (final period in [
      EarningsPeriod.week,
      EarningsPeriod.month,
      EarningsPeriod.year,
    ]) {
      for (final count in [0, 1, 5]) {
        testWidgets(
          '$period / $count件のデータで例外なく描画できる',
          (tester) async {
            await tester.pumpWidget(
              buildTestWidget(makeData(period: period, pointCount: count)),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('month期間で横方向ドラッグが例外なく完了する', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          makeData(period: EarningsPeriod.month, pointCount: 30),
        ),
      );
      final center = tester.getCenter(find.byType(GestureDetector));
      await tester.dragFrom(center, const Offset(40, 0));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('year期間で横方向ドラッグが例外なく完了する', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          makeData(period: EarningsPeriod.year, pointCount: 365),
        ),
      );
      final center = tester.getCenter(find.byType(GestureDetector));
      await tester.dragFrom(center, const Offset(-40, 0));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('期間切替でクラッシュしない（week→year）', (tester) async {
      final key = GlobalKey();
      Widget build(EarningsWindowData data) {
        return MaterialApp(
          home: Scaffold(
            body: CumulativeEarningsChart(key: key, data: data, height: 200),
          ),
        );
      }

      await tester.pumpWidget(
        build(makeData(period: EarningsPeriod.month, pointCount: 30)),
      );
      final center = tester.getCenter(find.byType(GestureDetector));
      await tester.dragFrom(center, const Offset(60, 0));
      await tester.pump();

      await tester.pumpWidget(
        build(makeData(period: EarningsPeriod.year, pointCount: 12)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
