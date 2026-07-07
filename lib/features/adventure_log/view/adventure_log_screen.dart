import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:task_manager/features/adventure_log/model/adventure_log_entry.dart';
import 'package:task_manager/features/adventure_log/model/daily_earning.dart';
import 'package:task_manager/features/adventure_log/providers/adventure_log_providers.dart';
import 'package:task_manager/features/adventure_log/providers/daily_earnings_providers.dart';
import 'package:task_manager/features/adventure_log/widgets/adventure_timeline_tile.dart';
import 'package:task_manager/features/adventure_log/widgets/cumulative_earnings_chart.dart';
import 'package:task_manager/features/adventure_log/widgets/daily_earnings_bar_chart.dart';
import 'package:task_manager/features/adventure_log/widgets/earnings_period_selector.dart';
import 'package:task_manager/widgets/empty_state_view.dart';
import 'package:task_manager/widgets/message_guard.dart';

class AdventureLogScreen extends ConsumerWidget {
  const AdventureLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(adventureLogEntriesProvider);
    final windowData = ref.watch(earningsWindowDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('冒険の記録')),
      body: MessageGuard(
        child: entriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('読み込みに失敗しました: $error')),
          data: (entries) =>
              _AdventureLogContent(entries: entries, windowData: windowData),
        ),
      ),
    );
  }
}

class _AdventureLogContent extends StatelessWidget {
  const _AdventureLogContent({required this.entries, required this.windowData});

  final List<AdventureLogEntry> entries;
  final EarningsWindowData? windowData;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final chartHeight = math.max(
      170.0,
      (mediaQuery.size.height - mediaQuery.padding.vertical - kToolbarHeight) /
          3,
    );

    final graphChildren = <Widget>[
      const EarningsPeriodSelector(),
      if (windowData == null)
        SizedBox(
          height: chartHeight,
          child: const Center(child: CircularProgressIndicator()),
        )
      else ...[
        CumulativeEarningsChart(data: windowData!, height: chartHeight),
        DailyEarningsBarChart(data: windowData!, height: chartHeight),
      ],
    ];

    if (entries.isEmpty) {
      return ListView(
        children: [
          ...graphChildren,
          const SizedBox(height: 80),
          const Center(
            child: EmptyStateView(
              icon: Icons.auto_stories_outlined,
              message: 'まだ冒険の記録がありません',
            ),
          ),
        ],
      );
    }

    final children = <Widget>[
      ...graphChildren,
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Text(
          'タイムライン',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
    ];

    DateTime? currentDay;
    for (final entry in entries) {
      final day = entry.occurredAt == null
          ? null
          : DateTime(entry.occurredAt!.year, entry.occurredAt!.month,
              entry.occurredAt!.day);
      final needsHeader = currentDay == null || day != currentDay;
      if (needsHeader) {
        currentDay = day;
        children.add(_DayHeader(day: day));
      }
      children.add(AdventureTimelineTile(entry: entry));
    }
    children.add(const SizedBox(height: 24));

    return ListView(children: children);
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final DateTime? day;

  @override
  Widget build(BuildContext context) {
    final text = day == null ? '日時未記録' : DateFormat('yyyy年M月d日').format(day!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
