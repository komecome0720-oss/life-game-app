import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/economy/model/budget_split.dart';
import 'package:task_manager/features/health/model/health_log.dart';
import 'package:task_manager/features/health/model/health_rollover.dart';
import 'package:task_manager/features/health/model/health_streak_state.dart';
import 'package:task_manager/features/health/model/health_scoring.dart';
import 'package:task_manager/features/health/viewmodel/health_detail_viewmodel.dart';
import 'package:task_manager/utils/health_goal.dart';

/// ストリークカレンダー（月表示）。各日=合計点数のみ。§5-B色で塗り分け。
/// 100%達成日は金枠＋王冠、フリーズ消費日はスノーフレーク。月送り可・今日を強調。
class HealthStreakCalendar extends ConsumerStatefulWidget {
  const HealthStreakCalendar({super.key, required this.streakState});

  final HealthStreakState streakState;

  @override
  ConsumerState<HealthStreakCalendar> createState() =>
      _HealthStreakCalendarState();
}

class _HealthStreakCalendarState extends ConsumerState<HealthStreakCalendar> {
  late DateTime _month; // 表示中の月（day=1に固定）
  Map<String, HealthLog> _logs = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final logs = await ref
          .read(healthDetailViewModelProvider.notifier)
          .fetchMonthLogs(_month);
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'カレンダーの読み込みに失敗しました: $e';
        _isLoading = false;
      });
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
    });
    _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  '連続カレンダー',
                  style: text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StreakStatusRow(streakState: widget.streakState),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: '前の月',
                ),
                Text(
                  '${_month.year}年${_month.month}月',
                  style: text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: '次の月',
                ),
              ],
            ),
            const SizedBox(height: 2),
            _WeekdayHeader(),
            const SizedBox(height: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _error!,
                  style: text.bodySmall?.copyWith(color: scheme.error),
                ),
              )
            else if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              _buildGrid(context),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final firstDay = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = firstDay.weekday % 7; // 日曜=0起点
    final todayKey = HealthRollover.dateKey(DateTime.now());

    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _dayCellFor(day, todayKey),
    ];

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      childAspectRatio: 1.5,
      children: cells,
    );
  }

  Widget _dayCellFor(int day, String todayKey) {
    final date = DateTime(_month.year, _month.month, day);
    final dateKey = HealthRollover.dateKey(date);
    return _DayCell(
      day: day,
      log: _logs[dateKey],
      isToday: dateKey == todayKey,
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  static const _labels = ['日', '月', '火', '水', '木', '金', '土'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        for (final label in _labels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: text.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// ストリークカレンダー見出しと同じ行に収める、連続日数・称号・フリーズ残数の
/// コンパクト表示。称号だけ長さが不定なため Flexible で省略可にする。
class _StreakStatusRow extends StatelessWidget {
  const _StreakStatusRow({required this.streakState});

  final HealthStreakState streakState;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = streakState.achievedTitles.isEmpty
        ? null
        : streakState.achievedTitles.last;

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 2,
      children: [
        _StatusChip(
          icon: Icons.local_fire_department,
          label: '${streakState.streakCount}日連続',
          color: scheme.primary,
        ),
        _StatusChip(
          icon: Icons.ac_unit,
          label: 'フリーズ${streakState.freezesRemaining}個',
          color: scheme.secondary,
        ),
        if (title != null)
          _StatusChip(
            icon: Icons.emoji_events,
            label: title,
            color: scheme.tertiary,
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 2),
        Text(
          label,
          style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.log,
    required this.isToday,
  });

  final int day;
  final HealthLog? log;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final text = Theme.of(context).textTheme;
    final hasLog = log != null;
    // achievedPercent は旧ログで未保存の場合があるため、totalScore から都度算出する。
    final ratio = hasLog
        ? HealthScoring.achievementRatio(
            log!.totalScore,
            HealthScoring.maxActiveScore(
              meditationEnabled: log!.meditationEnabledSnapshot,
            ),
          )
        : 0.0;
    final isPerfect = log?.dayOutcome == 'perfect';
    final isFrozen = log?.dayOutcome == 'frozen';
    final isStreakHit = hasLog && ratio >= kHealthStreakRatio;
    final color = hasLog
        ? healthTotalColor(ratio, brightness)
        : scheme.outlineVariant;

    return Container(
      decoration: BoxDecoration(
        color: hasLog ? color.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPerfect
              ? Colors.amber.shade600
              : isToday
              ? scheme.primary
              : color.withValues(alpha: hasLog ? 0.4 : 0.15),
          width: isPerfect || isToday ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4),
            child: Text(
              '$day',
              style: text.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          if (hasLog)
            Align(
              child: Container(
                padding: isStreakHit
                    ? const EdgeInsets.symmetric(horizontal: 5, vertical: 1)
                    : EdgeInsets.zero,
                decoration: isStreakHit
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 1.5),
                      )
                    : null,
                child: Text(
                  '${log!.totalScore}',
                  style: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
          if (isPerfect)
            const Positioned(
              top: 2,
              right: 2,
              child: Icon(Icons.emoji_events, size: 12, color: Colors.amber),
            ),
          if (isFrozen)
            Positioned(
              top: 2,
              right: 2,
              child: Icon(Icons.ac_unit, size: 12, color: scheme.secondary),
            ),
        ],
      ),
    );
  }
}
