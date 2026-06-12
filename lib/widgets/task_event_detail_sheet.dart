import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/theme/app_tokens.dart';
import 'package:task_manager/utils/app_messenger.dart';

/// タイマー列と実績分列のラベル行を同じ高さにそろえる（ヘルプアイコン行とテキストのみ行のズレ防止）。
const double _kTimerSectionLabelRowHeight = 48;

/// 完了処理コールバック。
/// [predictedMinutes] はカレンダー枠（ToDoなら estimatedMinutes）から計算した見込時間。
/// [actualMinutes] は実績時間。null の場合は「ログなし完了」を意味する。
typedef TaskCompleteCallback =
    Future<void> Function({
      required int predictedMinutes,
      required int? actualMinutes,
    });

/// タイマー一時停止時に、未了のまま見込み・実績分を保存するコールバック。
typedef TaskPauseAndSaveCallback =
    Future<void> Function({
      required int predictedMinutes,
      required int actualMinutes,
    });

/// 「保存」ボタン押下時に、ステータスは変えずに現状の進捗（実績時間など）だけを保存するコールバック。
typedef TaskSaveProgressCallback =
    Future<void> Function({
      required int predictedMinutes,
      required int actualMinutes,
    });

/// 開始・終了時刻が変更されたときに呼ばれるコールバック。
/// 戻り値 true で成功扱いとし、シート側の表示を更新する。
typedef TaskTimesChangedCallback =
    Future<bool> Function({
      required DateTime newStart,
      required DateTime newEnd,
    });

/// 予定タップ時のボトムシート: 見込時間・報酬・タイマー・実績入力・完了 + 編集/複製/削除
///
/// [predictedMinutes] と [expectedRewardYen] は呼び出し側で計算して渡す
/// （シートは Riverpod 非依存に保つため）。
/// [onTimerStart] はタイマー開始時に呼ばれる（戻り値は未使用、呼び出し側で DB 保存可能）。
/// [onPauseAndSave] はタイマー一時停止時に呼ばれる（未了のまま進捗保存する用途）。
/// [onSaveProgress] は「保存」ボタン押下時に呼ばれる。ステータスは変えずに、
/// 現状の実績時間など進捗だけをコレクションへ保存する用途（タイマーは止めない）。
/// [onRevert] は task.isCompleted=true のとき「未了に戻す」ボタンから呼ばれる。
/// 戻り値 true なら未了化に成功した扱いとし、シートを開いたまま操作を再開できるようにする。
/// [onTimesChanged] は開始・終了時刻が編集されたときに呼ばれる。
Future<void> showTaskEventDetailSheet({
  required BuildContext context,
  required CalendarTask task,
  required int predictedMinutes,
  required int expectedRewardYen,
  required TaskCompleteCallback onComplete,
  Future<void> Function()? onTimerStart,
  TaskPauseAndSaveCallback? onPauseAndSave,
  TaskSaveProgressCallback? onSaveProgress,
  Future<bool> Function()? onRevert,
  TaskTimesChangedCallback? onTimesChanged,
  VoidCallback? onEdit,
  VoidCallback? onDuplicate,
  VoidCallback? onDelete,
  Future<void> Function(Quadrant quadrant)? onQuadrantChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _TaskEventDetailBody(
        task: task,
        predictedMinutes: predictedMinutes,
        expectedRewardYen: expectedRewardYen,
        onComplete: onComplete,
        onTimerStart: onTimerStart,
        onPauseAndSave: onPauseAndSave,
        onSaveProgress: onSaveProgress,
        onRevert: onRevert,
        onTimesChanged: onTimesChanged,
        onEdit: onEdit,
        onDuplicate: onDuplicate,
        onDelete: onDelete,
        onQuadrantChanged: onQuadrantChanged,
      ),
    ),
  );
}

/// 実績「分」入力欄の幅（半角数字4桁＋内側パディング・枠線ぶん）。
double _fourDigitMinutesFieldWidth(BuildContext context) {
  final style = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
  final painter = TextPainter(
    text: TextSpan(
      text: '0000',
      style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  const horizontalContentPadding = 8.0 * 2;
  const decorationSlack = 20.0;
  return painter.width + horizontalContentPadding + decorationSlack;
}

class _TaskEventDetailBody extends StatefulWidget {
  const _TaskEventDetailBody({
    required this.task,
    required this.predictedMinutes,
    required this.expectedRewardYen,
    required this.onComplete,
    this.onTimerStart,
    this.onPauseAndSave,
    this.onSaveProgress,
    this.onRevert,
    this.onTimesChanged,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onQuadrantChanged,
  });

  final CalendarTask task;
  final int predictedMinutes;
  final int expectedRewardYen;
  final TaskCompleteCallback onComplete;
  final Future<void> Function()? onTimerStart;
  final TaskPauseAndSaveCallback? onPauseAndSave;
  final TaskSaveProgressCallback? onSaveProgress;
  final Future<bool> Function()? onRevert;
  final TaskTimesChangedCallback? onTimesChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final Future<void> Function(Quadrant quadrant)? onQuadrantChanged;

  @override
  State<_TaskEventDetailBody> createState() => _TaskEventDetailBodyState();
}

class _TaskEventDetailBodyState extends State<_TaskEventDetailBody> {
  Stopwatch? _stopwatch;
  Timer? _ticker;
  final TextEditingController _actualMinutesCtrl = TextEditingController();
  final FocusNode _actualMinutesFocus = FocusNode();

  // 現在のタイマーセッション（リセット〜次のリセットまで）開始時のフィールド値。
  // 一時停止のたびに `_baselineMinutes + 経過分(秒切り捨て)` をフィールドへ転記する。
  int _baselineMinutes = 0;
  bool _needsBaselineCapture = true;

  // 完了状態は未了に戻す操作で書き換わる可能性があるので、シート内で保持する。
  // late にしない（ホットリロードで State が再利用されると initState が走らず未初期化になる）。
  bool _isCompleted = false;

  // 開始・終了時刻はシート内で編集できる。null は ToDo（カレンダー枠なし）。
  DateTime? _currentStart;
  DateTime? _currentEnd;

  late Quadrant _currentQuadrant;

  @override
  void initState() {
    super.initState();
    // 完了済み・未完了どちらでも、過去に記録された実績時間があれば初期表示する。
    final saved = widget.task.actualMinutes;
    if (saved != null && saved > 0) {
      _actualMinutesCtrl.text = saved.toString();
    }
    _isCompleted = widget.task.isCompleted;
    _currentStart = widget.task.start;
    _currentEnd = widget.task.end;
    _currentQuadrant = QuadrantX.from(
      urgency: widget.task.urgency,
      importance: widget.task.importance,
    );
  }

  @override
  void didUpdateWidget(covariant _TaskEventDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id ||
        oldWidget.task.isCompleted != widget.task.isCompleted) {
      _isCompleted = widget.task.isCompleted;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _actualMinutesCtrl.dispose();
    _actualMinutesFocus.dispose();
    super.dispose();
  }

  Future<void> _toggleTimer() async {
    if (_stopwatch?.isRunning ?? false) {
      // 一時停止：停止 + フィールドへ転記（baseline + 経過分・秒切り捨て）
      _stopwatch!.stop();
      _ticker?.cancel();
      _ticker = null;
      _writeElapsedToField();
      final pauseSave = widget.onPauseAndSave;
      if (pauseSave != null) {
        final actual =
            int.tryParse(_actualMinutesCtrl.text.trim()) ?? 0;
        try {
          await pauseSave(
            predictedMinutes: widget.predictedMinutes,
            actualMinutes: actual,
          );
        } catch (_) {
          /* 呼び出し側でメッセージ表示 */
        }
      }
    } else {
      // 開始：DB未保存（リモート表示中）なら、この時点でアプリタスクとして保存する。
      // 既にDB保存済みなら onTimerStart 側の findTaskIdByExternalId で no-op。
      if (widget.onTimerStart != null && _stopwatch == null) {
        try {
          await widget.onTimerStart!();
        } catch (_) {
          /* 保存失敗でもタイマーは継続 */
        }
      }
      // セッション開始時のフィールド値を baseline として保持。
      // 同一セッション内（pause→resume）では再取得しない。
      if (_needsBaselineCapture) {
        _baselineMinutes = int.tryParse(_actualMinutesCtrl.text.trim()) ?? 0;
        _needsBaselineCapture = false;
      }
      _stopwatch ??= Stopwatch();
      _stopwatch!.start();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    if (mounted) setState(() {});
  }

  /// 現在のタイマー経過分（秒切り捨て）を baseline と合算してフィールドへ書き込む。
  void _writeElapsedToField() {
    final elapsedSec = _stopwatch?.elapsed.inSeconds ?? 0;
    final addedMinutes = elapsedSec ~/ 60;
    _actualMinutesCtrl.text = (_baselineMinutes + addedMinutes).toString();
  }

  void _showTimerHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('タイマーの使い方'),
        content: const SingleChildScrollView(
          child: Text(
            '・一時停止すると、計測した時間が右の「実際にかかった時間」へ自動で追加されます。\n'
            '・「実際にかかった時間」の値は手動で書き換えられます。\n'
            '・「リセット」ボタンを押しても、「実際にかかった時間」の値は保持されます。\n'
            '・リセット後に再スタートして一時停止すると、その時点の「実際にかかった時間」に '
            '新しい計測分が加算されます。\n'
            '　例）「実際にかかった時間」が 25 分の状態で、リセット → スタート → 3:22 で一時停止 → 28 分。\n'
            '・タイマーを動かしたまま「完了」を押した場合は、自動で一時停止と転記をしてから完了します。',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// リセット：タイマー表示を 0 に戻し、次回 start で baseline を再取得させる。
  /// 「実際にかかった時間」フィールドの値は保持する。
  void _resetTimer() {
    _ticker?.cancel();
    _ticker = null;
    _stopwatch?.stop();
    _stopwatch?.reset();
    _needsBaselineCapture = true;
    if (mounted) setState(() {});
  }

  String _elapsedLabel() {
    final d = _stopwatch?.elapsed ?? Duration.zero;
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatHm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// CupertinoDatePicker（time モード・1分刻み）で時刻を選択させる。
  /// 戻り値は元の日付を保ったまま、時・分のみを入れ替えた DateTime。
  Future<DateTime?> _pickTime(DateTime initial) async {
    DateTime tentative = DateTime(
      initial.year,
      initial.month,
      initial.day,
      initial.hour,
      initial.minute,
    );
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => Container(
        height: 280 + MediaQuery.paddingOf(ctx).top,
        color: CupertinoColors.systemBackground.resolveFrom(ctx),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('キャンセル'),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('決定'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  minuteInterval: 1,
                  initialDateTime: tentative,
                  onDateTimeChanged: (v) => tentative = v,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return null;
    return DateTime(
      initial.year,
      initial.month,
      initial.day,
      tentative.hour,
      tentative.minute,
    );
  }

  Future<void> _onTapStart() async {
    final cur = _currentStart;
    if (cur == null) return;
    final picked = await _pickTime(cur);
    if (picked == null) return;
    final newEnd = _currentEnd ?? picked.add(const Duration(minutes: 30));
    if (!picked.isBefore(newEnd)) {
      _showInvalidRangeMessage();
      return;
    }
    await _applyTimeChange(newStart: picked, newEnd: newEnd);
  }

  Future<void> _onTapEnd() async {
    final cur = _currentEnd;
    if (cur == null) return;
    final picked = await _pickTime(cur);
    if (picked == null) return;
    final newStart = _currentStart ?? picked.subtract(const Duration(minutes: 30));
    if (!newStart.isBefore(picked)) {
      _showInvalidRangeMessage();
      return;
    }
    await _applyTimeChange(newStart: newStart, newEnd: picked);
  }

  void _showInvalidRangeMessage() {
    showAppSnackBar(
      context,
      const SnackBar(content: Text('終了時刻は開始時刻より後にしてください')),
    );
  }

  Future<void> _applyTimeChange({
    required DateTime newStart,
    required DateTime newEnd,
  }) async {
    final cb = widget.onTimesChanged;
    final prevStart = _currentStart;
    final prevEnd = _currentEnd;
    setState(() {
      _currentStart = newStart;
      _currentEnd = newEnd;
    });
    if (cb == null) return;
    final ok = await cb(newStart: newStart, newEnd: newEnd);
    if (!mounted) return;
    if (!ok) {
      // 失敗時は表示を巻き戻す。
      setState(() {
        _currentStart = prevStart;
        _currentEnd = prevEnd;
      });
    }
  }

  Future<void> _onTapRevert() async {
    _ticker?.cancel();
    final cb = widget.onRevert;
    if (cb == null) return;
    final ok = await cb();
    if (!mounted) return;
    if (ok) {
      // タイマー・実績入力を再操作できるように、完了フラグだけ戻す。
      // タイマー自体はリセット状態（次の start で baseline 再取得）にしておく。
      _stopwatch?.stop();
      _stopwatch?.reset();
      _ticker?.cancel();
      _ticker = null;
      _needsBaselineCapture = true;
      setState(() {
        _isCompleted = false;
      });
    }
  }

  /// 「保存」ボタン：ステータスは変えずに、現状の進捗（実績時間など）だけを
  /// コレクションへ保存する。保存後はシートを閉じてホーム画面に戻り、
  /// 呼び出し側でスナックバーを表示する想定。
  Future<void> _onTapSave() async {
    final cb = widget.onSaveProgress;
    if (cb == null) return;

    // 走行中なら停止して現時点の経過分をフィールドへ反映（保存して帰るため）。
    if (_stopwatch?.isRunning ?? false) {
      _stopwatch!.stop();
      _ticker?.cancel();
      _ticker = null;
      _writeElapsedToField();
    }

    final actual = int.tryParse(_actualMinutesCtrl.text.trim()) ?? 0;
    _ticker?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
    try {
      await cb(
        predictedMinutes: widget.predictedMinutes,
        actualMinutes: actual,
      );
    } catch (_) {
      /* 呼び出し側でメッセージ表示 */
    }
  }

  Future<void> _onTapComplete() async {
    // 走行中なら一時停止扱いにして転記（最新の経過分をフィールドへ反映）。
    if (_stopwatch?.isRunning ?? false) {
      _stopwatch!.stop();
      _ticker?.cancel();
      _ticker = null;
      _writeElapsedToField();
      if (mounted) setState(() {});
    }

    final fieldText = _actualMinutesCtrl.text.trim();
    final fieldMinutes = int.tryParse(fieldText);
    final fieldHasValue = fieldMinutes != null && fieldMinutes > 0;

    if (!fieldHasValue) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('時間ログなしで完了しますか？'),
          content: const Text('時間予測ログが残りませんがよろしいですか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('いいえ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('はい'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    final actual = fieldHasValue ? fieldMinutes : null;

    _ticker?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
    await widget.onComplete(
      predictedMinutes: widget.predictedMinutes,
      actualMinutes: actual,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final running = _stopwatch?.isRunning ?? false;
    final predictedLabel = widget.predictedMinutes > 0
        ? '${widget.predictedMinutes}分'
        : '—';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.task.title,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (_currentStart != null && _currentEnd != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _TimeChip(
                      label: '開始',
                      time: _formatHm(_currentStart!),
                      onTap: _isCompleted ? null : _onTapStart,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('〜', style: text.titleMedium),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TimeChip(
                      label: '終了',
                      time: _formatHm(_currentEnd!),
                      onTap: _isCompleted ? null : _onTapEnd,
                    ),
                  ),
                ],
              ),
            ],
            if (widget.onQuadrantChanged != null) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTapUp: (details) async {
                  final selected = await showMenu<Quadrant>(
                    context: context,
                    position: RelativeRect.fromLTRB(
                      details.globalPosition.dx,
                      details.globalPosition.dy,
                      details.globalPosition.dx,
                      details.globalPosition.dy,
                    ),
                    items: Quadrant.values.map((q) {
                      final isCurrent = q == _currentQuadrant;
                      return PopupMenuItem<Quadrant>(
                        value: q,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: q.accentColor(scheme),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              q.label,
                              style: TextStyle(
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            if (isCurrent) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.check,
                                  size: 16, color: scheme.primary),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  );
                  if (selected == null || selected == _currentQuadrant) return;
                  setState(() => _currentQuadrant = selected);
                  await widget.onQuadrantChanged!(selected);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _currentQuadrant
                        .backgroundColor(scheme),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _currentQuadrant.accentColor(scheme)
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _currentQuadrant.accentColor(scheme),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '領域 ${_currentQuadrant.label}',
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.unfold_more,
                          size: 18, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _RewardCard(
              predictedLabel: predictedLabel,
              expectedRewardYen: widget.expectedRewardYen,
            ),
            const SizedBox(height: 16),
            _TimerAndActualRow(
              isCompleted: _isCompleted,
              running: running,
              elapsedLabel: _elapsedLabel(),
              canResetTimer: !running && (_stopwatch?.elapsed.inSeconds ?? 0) > 0,
              onToggle: _toggleTimer,
              onReset: _resetTimer,
              onShowHelp: _showTimerHelp,
              controller: _actualMinutesCtrl,
              focusNode: _actualMinutesFocus,
            ),
            const SizedBox(height: 20),
            if (_isCompleted && widget.onRevert != null)
              FilledButton.icon(
                onPressed: _onTapRevert,
                icon: const Icon(Icons.replay_rounded),
                label: const Text('未了に戻す'),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed:
                          widget.onSaveProgress == null ? null : _onTapSave,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text(
                        '保存',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _onTapComplete,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text(
                        '完了',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            if (widget.onEdit != null ||
                widget.onDuplicate != null ||
                widget.onDelete != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (widget.onEdit != null)
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () {
                          _ticker?.cancel();
                          Navigator.of(context).pop();
                          widget.onEdit!();
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('編集'),
                      ),
                    ),
                  if (widget.onDuplicate != null)
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () {
                          _ticker?.cancel();
                          Navigator.of(context).pop();
                          widget.onDuplicate!();
                        },
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('複製'),
                      ),
                    ),
                  if (widget.onDelete != null)
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () {
                          _ticker?.cancel();
                          Navigator.of(context).pop();
                          widget.onDelete!();
                        },
                        icon: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        label: Text(
                          '削除',
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

}

String _formatYen(int n) {
  return n.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({required this.predictedLabel, required this.expectedRewardYen});

  final String predictedLabel;
  final int expectedRewardYen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                '見込時間：$predictedLabel',
                style: text.bodyMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.paid_outlined, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'このタスクを達成すると',
                  style: text.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
                ),
              ),
              Text(
                '¥${_formatYen(expectedRewardYen)}',
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final String time;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(
            alpha: disabled ? 0.4 : 1.0,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Text(
              time,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: disabled ? scheme.onSurfaceVariant : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerAndActualRow extends StatelessWidget {
  const _TimerAndActualRow({
    required this.isCompleted,
    required this.running,
    required this.elapsedLabel,
    required this.canResetTimer,
    required this.onToggle,
    required this.onReset,
    required this.onShowHelp,
    required this.controller,
    required this.focusNode,
  });

  final bool isCompleted;
  final bool running;
  final String elapsedLabel;
  final bool canResetTimer;
  final VoidCallback onToggle;
  final VoidCallback onReset;
  final VoidCallback onShowHelp;
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return IgnorePointer(
      ignoring: isCompleted,
      child: Opacity(
        opacity: isCompleted ? 0.4 : 1.0,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: _kTimerSectionLabelRowHeight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('タイマー', style: text.labelLarge),
                        IconButton(
                          onPressed: onShowHelp,
                          icon: const Icon(Icons.help_outline),
                          tooltip: 'タイマーの使い方',
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          constraints: const BoxConstraints(),
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 48,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: onToggle,
                                  icon: Icon(
                                    running
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                  label: Text(running ? '一時停止' : 'スタート'),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  elapsedLabel,
                                  style: text.titleMedium?.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                // 一時停止中（経過 > 0）のみ有効
                                IconButton(
                                  onPressed: canResetTimer ? onReset : null,
                                  icon: const Icon(Icons.refresh_rounded),
                                  tooltip: 'リセット',
                                  visualDensity: VisualDensity.compact,
                                  style: IconButton.styleFrom(
                                    shape: const CircleBorder(),
                                    side: BorderSide(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: _kTimerSectionLabelRowHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '実際にかかった時間',
                      style: text.labelLarge,
                      softWrap: true,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: _fourDigitMinutesFieldWidth(context),
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: false,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          textAlign: TextAlign.end,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text('分', style: text.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
