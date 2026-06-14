import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/theme/app_tokens.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/task_detail/quadrant_selector.dart';

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

/// タイトル・象限・時刻を一括保存するコールバック。
/// 戻り値 true で保存成功、false でエラー（シートは閉じない）。
typedef TaskSaveEditsCallback =
    Future<bool> Function({
      required String title,
      required Quadrant quadrant,
      required DateTime? start,
      required DateTime? end,
    });

/// 予定タップ時のボトムシート: 見込時間・報酬・タイマー・実績入力・完了 + 編集/複製/削除
///
/// [predictedMinutes] と [expectedRewardYen] は呼び出し側で計算して渡す（Riverpod非依存）。
/// [calcReward] は編集後の見込時間から報酬を再計算する関数（ライブ更新用）。
/// [onSaveEdits] はタイトル・象限・開始/終了時刻を一括保存するコールバック。
/// [onTimerStart] はタイマー開始時に呼ばれる。
/// [onPauseAndSave] はタイマー一時停止時に呼ばれる（未了のまま進捗保存）。
/// [onSaveProgress] は「保存」ボタン押下時に呼ばれる（進捗のみ保存）。
/// [onRevert] は task.isCompleted=true のとき「未了に戻す」ボタンから呼ばれる。
Future<void> showTaskEventDetailSheet({
  required BuildContext context,
  required CalendarTask task,
  required int predictedMinutes,
  required int expectedRewardYen,
  required TaskCompleteCallback onComplete,
  int Function(int minutes)? calcReward,
  TaskSaveEditsCallback? onSaveEdits,
  Future<void> Function()? onTimerStart,
  TaskPauseAndSaveCallback? onPauseAndSave,
  TaskSaveProgressCallback? onSaveProgress,
  Future<bool> Function()? onRevert,
  VoidCallback? onEdit,
  VoidCallback? onDuplicate,
  VoidCallback? onDelete,
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
        calcReward: calcReward,
        onSaveEdits: onSaveEdits,
        onTimerStart: onTimerStart,
        onPauseAndSave: onPauseAndSave,
        onSaveProgress: onSaveProgress,
        onRevert: onRevert,
        onEdit: onEdit,
        onDuplicate: onDuplicate,
        onDelete: onDelete,
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
    this.calcReward,
    this.onSaveEdits,
    this.onTimerStart,
    this.onPauseAndSave,
    this.onSaveProgress,
    this.onRevert,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
  });

  final CalendarTask task;
  final int predictedMinutes;
  final int expectedRewardYen;
  final TaskCompleteCallback onComplete;
  final int Function(int minutes)? calcReward;
  final TaskSaveEditsCallback? onSaveEdits;
  final Future<void> Function()? onTimerStart;
  final TaskPauseAndSaveCallback? onPauseAndSave;
  final TaskSaveProgressCallback? onSaveProgress;
  final Future<bool> Function()? onRevert;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  @override
  State<_TaskEventDetailBody> createState() => _TaskEventDetailBodyState();
}

class _TaskEventDetailBodyState extends State<_TaskEventDetailBody> {
  Stopwatch? _stopwatch;
  Timer? _ticker;
  late final TextEditingController _titleCtrl;
  final TextEditingController _actualMinutesCtrl = TextEditingController();
  final FocusNode _actualMinutesFocus = FocusNode();

  // 現在のタイマーセッション（リセット〜次のリセットまで）開始時のフィールド値。
  // 一時停止のたびに `_baselineMinutes + 経過分(秒切り捨て)` をフィールドへ転記する。
  int _baselineMinutes = 0;
  bool _needsBaselineCapture = true;

  // 完了状態は未了に戻す操作で書き換わる可能性があるので、シート内で保持する。
  bool _isCompleted = false;
  bool _isSavingEdits = false;

  // 開始・終了時刻はシート内で編集できる。null は ToDo（カレンダー枠なし）。
  DateTime? _currentStart;
  DateTime? _currentEnd;

  late Quadrant _currentQuadrant;

  bool get _isDirty {
    if (_titleCtrl.text.trim() != widget.task.title) return true;
    if (_currentStart != widget.task.start) return true;
    if (_currentEnd != widget.task.end) return true;
    if (_currentQuadrant != QuadrantX.from(
      urgency: widget.task.urgency,
      importance: widget.task.importance,
    )) { return true; }
    return false;
  }

  /// ステージ後の start/end から算出した見込時間（分）。
  int get _livePredictedMinutes {
    final s = _currentStart;
    final e = _currentEnd;
    if (s != null && e != null) {
      final m = e.difference(s).inMinutes;
      if (m > 0) return m.clamp(1, 24 * 60);
    }
    return widget.predictedMinutes;
  }

  int get _liveRewardYen {
    final calc = widget.calcReward;
    if (calc != null) return calc(_livePredictedMinutes);
    return widget.expectedRewardYen;
  }

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.task.title);
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
    _titleCtrl.dispose();
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
            predictedMinutes: _livePredictedMinutes,
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
    _applyTimeChange(newStart: picked, newEnd: newEnd);
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
    _applyTimeChange(newStart: newStart, newEnd: picked);
  }

  void _showInvalidRangeMessage() {
    showAppSnackBar(
      context,
      const SnackBar(content: Text('終了時刻は開始時刻より後にしてください')),
    );
  }

  void _applyTimeChange({
    required DateTime newStart,
    required DateTime newEnd,
  }) {
    setState(() {
      _currentStart = newStart;
      _currentEnd = newEnd;
    });
  }

  /// 「変更を保存」ボタン：タイトル・象限・開始/終了を一括保存。
  Future<void> _onTapSaveEdits() async {
    final cb = widget.onSaveEdits;
    if (cb == null) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _isSavingEdits = true);
    try {
      final ok = await cb(
        title: title,
        quadrant: _currentQuadrant,
        start: _currentStart,
        end: _currentEnd,
      );
      if (!mounted) return;
      if (ok) {
        showAppSnackBar(context, const SnackBar(content: Text('保存しました')));
      } else {
        showAppSnackBar(context, const SnackBar(content: Text('保存に失敗しました')));
      }
    } finally {
      if (mounted) setState(() => _isSavingEdits = false);
    }
  }

  Future<bool> _onWillPop() async {
    if (!_isDirty) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('変更を保存しますか？'),
        content: const Text('タイトル・領域・時刻の変更が保存されていません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('破棄'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == 'save') {
      await _onTapSaveEdits();
      return true;
    }
    return result == 'discard';
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
        predictedMinutes: _livePredictedMinutes,
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
      predictedMinutes: _livePredictedMinutes,
      actualMinutes: actual,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final running = _stopwatch?.isRunning ?? false;
    final liveMinutes = _livePredictedMinutes;
    final predictedLabel = liveMinutes > 0 ? '$liveMinutes分' : '—';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final canLeave = await _onWillPop();
        if (canLeave) nav.pop();
      },
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 種別チップ
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '予定',
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // タイトル（インライン編集）
              TextField(
                controller: _titleCtrl,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                decoration: const InputDecoration(
                  hintText: 'タイトル',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) => setState(() {}),
                enabled: !_isCompleted,
              ),
              // 時刻チップ
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
              // 領域セレクター
              const SizedBox(height: 12),
              Text('領域', style: text.labelMedium),
              const SizedBox(height: 8),
              QuadrantSelector(
                selected: _currentQuadrant,
                onSelect: (q) => setState(() => _currentQuadrant = q),
                enabled: !_isCompleted,
              ),
              // 報酬カード（ライブ更新）
              const SizedBox(height: 12),
              _RewardCard(
                predictedLabel: predictedLabel,
                expectedRewardYen: _liveRewardYen,
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
              const SizedBox(height: 16),
              // 変更を保存ボタン（dirty時のみ活性）
              if (widget.onSaveEdits != null)
                FilledButton.tonalIcon(
                  onPressed: (_isDirty && !_isSavingEdits) ? _onTapSaveEdits : null,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_isDirty ? '変更を保存' : '保存済み'),
                ),
              const SizedBox(height: 8),
              _CompleteOrRevertRow(
                isCompleted: _isCompleted,
                onComplete: _onTapComplete,
                onSave: widget.onSaveProgress == null ? null : _onTapSave,
                onRevert: widget.onRevert == null ? null : _onTapRevert,
              ),
              _ActionButtonsRow(
                onEdit: widget.onEdit == null ? null : () {
                  _ticker?.cancel();
                  Navigator.of(context).pop();
                  widget.onEdit!();
                },
                onDuplicate: widget.onDuplicate == null ? null : () {
                  _ticker?.cancel();
                  Navigator.of(context).pop();
                  widget.onDuplicate!();
                },
                onDelete: widget.onDelete == null ? null : () {
                  _ticker?.cancel();
                  Navigator.of(context).pop();
                  widget.onDelete!();
                },
              ),
            ],
          ),
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

/// Key for the actual-minutes text field — used in widget tests.
const Key kActualMinutesFieldKey = Key('actual_minutes_field');

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
                          key: kActualMinutesFieldKey,
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


class _CompleteOrRevertRow extends StatelessWidget {
  const _CompleteOrRevertRow({
    required this.isCompleted,
    required this.onComplete,
    this.onSave,
    this.onRevert,
  });

  final bool isCompleted;
  final VoidCallback onComplete;
  final VoidCallback? onSave;
  final VoidCallback? onRevert;

  @override
  Widget build(BuildContext context) {
    if (isCompleted && onRevert != null) {
      return FilledButton.icon(
        onPressed: onRevert,
        icon: const Icon(Icons.replay_rounded),
        label: const Text('未了に戻す'),
      );
    }
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存', overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: FilledButton.icon(
            onPressed: onComplete,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('完了', overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}

class _ActionButtonsRow extends StatelessWidget {
  const _ActionButtonsRow({this.onEdit, this.onDuplicate, this.onDelete});

  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    if (onEdit == null && onDuplicate == null && onDelete == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 4),
        Row(
          children: [
            if (onEdit != null)
              Expanded(
                child: TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('編集'),
                ),
              ),
            if (onDuplicate != null)
              Expanded(
                child: TextButton.icon(
                  onPressed: onDuplicate,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('複製'),
                ),
              ),
            if (onDelete != null)
              Expanded(
                child: TextButton.icon(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  label: Text('削除', style: TextStyle(color: scheme.error)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
