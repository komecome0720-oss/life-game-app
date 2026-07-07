import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/adventure_log/model/daily_earning.dart';
import 'package:task_manager/features/adventure_log/providers/daily_earnings_providers.dart';

class EarningsPeriodSelector extends ConsumerWidget {
  const EarningsPeriodSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(earningsPeriodProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: SegmentedButton<EarningsPeriod>(
          segments: [
            for (final p in EarningsPeriod.values)
              ButtonSegment(value: p, label: Text(p.label)),
          ],
          selected: {period},
          onSelectionChanged: (set) =>
              ref.read(earningsPeriodProvider.notifier).set(set.first),
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            ),
            textStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}
