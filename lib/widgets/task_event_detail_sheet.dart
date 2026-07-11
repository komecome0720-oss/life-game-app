import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:task_manager/features/pomodoro/view/pomodoro_settings_screen.dart';
import 'package:task_manager/features/prediction_accuracy/model/prediction_accuracy_config.dart';
import 'package:task_manager/features/timer/model/task_sheet_result.dart';
import 'package:task_manager/features/timer/widgets/split_start_button.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/theme/app_tokens.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/draggable_detail_sheet.dart';
import 'package:task_manager/widgets/task_detail/quadrant_selector.dart';

/// 大型一体型スタートボタンの高さ。「現状」列もこの高さ内に収める。
const double _kStartButtonHeight = kSplitStartButtonHeight;

/// 完了処理コールバック。
/// [predictedMinutes] はカレンダー枠（ToDoなら estimatedMinutes）から計算した見込時間。
/// [actualMinutes] は実績時間。null の場合は「ログなし完了」を意味する。
typedef TaskCompleteCallback =
    Future<void> Function({
      required int predictedMinutes,
      required int? actualMinutes,
    });

/// 開始・終了時刻が変更されたときに呼ばれるコールバック。
/// 戻り値 true で成功扱いとし、シート側の表示を更新する。
typedef TaskTimesChangedCallback =
    Future<bool> Function({
      required DateTime newStart,
      required DateTime newEnd,
    });

/// タイトル・象限・時刻＋進捗（実績分）を一括保存するコールバック。
/// 戻り値 true で保存成功、false でエラー（シートは閉じない）。
typedef TaskSaveEditsCallback =
    Future<bool> Function({
      required String title,
      required Quadrant quadrant,
      required DateTime? start,
      required DateTime? end,
      required int predictedMinutes,
      required int actualMinutes,
    });

/// 予定タップ時のボトムシート: 見込時間・報酬・スタート・実績入力・完了 + 編集/複製/削除
///
/// [predictedMinutes] と [expectedRewardYen] は呼び出し側で計算して渡す（Riverpod非依存）。
/// [calcReward] は編集後の見込時間から報酬を再計算する関数（ライブ更新用）。
/// [onSaveEdits] はタイトル・象限・開始/終了時刻を一括保存するコールバック。
/// [onRevert] は task.isCompleted=true のとき「未了に戻す」ボタンから呼ばれる。
///
/// 戻り値が [TaskSheetResult.startTimer] の場合、呼び出し側は安定した context で
/// `TimerLockLauncher.openForStart` を呼んでロック画面を起動する（このシート自身は
/// タイマー開始処理を行わない。詳細は `lib/features/timer/view/timer_lock_launcher.dart`）。
Future<TaskSheetResult?> showTaskEventDetailSheet({
  required BuildContext context,
  required CalendarTask task,
  required int predictedMinutes,
  required int expectedRewardYen,
  required TaskCompleteCallback onComplete,
  int defaultDurationMinutes = 60,
  int Function(int minutes)? calcReward,
  TaskSaveEditsCallback? onSaveEdits,
  Future<bool> Function()? onRevert,
  VoidCallback? onEdit,
  VoidCallback? onDuplicate,
  VoidCallback? onDelete,
}) {
  return showDraggableDetailSheet<TaskSheetResult>(
    context: context,
    builder: (context, scrollController) => _TaskEventDetailBody(
      task: task,
      predictedMinutes: predictedMinutes,
      expectedRewardYen: expectedRewardYen,
      onComplete: onComplete,
      defaultDurationMinutes: defaultDurationMinutes,
      calcReward: calcReward,
      onSaveEdits: onSaveEdits,
      onRevert: onRevert,
      onEdit: onEdit,
      onDuplicate: onDuplicate,
      onDelete: onDelete,
      scrollController: scrollController,
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
    this.defaultDurationMinutes = 60,
    this.calcReward,
    this.onSaveEdits,
    this.onRevert,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.scrollController,
  });

  final CalendarTask task;
  final int predictedMinutes;
  final int expectedRewardYen;
  final TaskCompleteCallback onComplete;
  final int defaultDurationMinutes;
  final int Function(int minutes)? calcReward;
  final TaskSaveEditsCallback? onSaveEdits;
  final Future<bool> Function()? onRevert;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final ScrollController? scrollController;

  @override
  State<_TaskEventDetailBody> createState() => _TaskEventDetailBodyState();
}

class _TaskEventDetailBodyState extends State<_TaskEventDetailBody> {
  late final TextEditingController _titleCtrl;
  final TextEditingController _actualMinutesCtrl = TextEditingController();
  final FocusNode _actualMinutesFocus = FocusNode();

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

  /// ステージ後の start/end から算出した報酬計算用の「分」（枠の長さ）。
  /// 精度ゲーム（宣言）とは別物（確定仕様16）。報酬ライブ計算と
  /// onSaveEdits(predictedMinutes:) への受け渡しに使う。旧名 `_livePredictedMinutes`。
  int get _plannedLiveMinutes {
    final s = _currentStart;
    final e = _currentEnd;
    if (s != null && e != null) {
      final m = e.difference(s).inMinutes;
      if (m > 0) return m.clamp(1, 24 * 60);
    }
    return widget.predictedMinutes;
  }

  /// 宣言済み予測（分）。未宣言なら null（「未宣言」表示・統計対象外）。
  /// 宣言済み manual 予定はステージ中の枠の分数（枠リサイズ＝再宣言のライブプレビュー）、
  /// 宣言済み googleCalendar 予定は estimatedMinutes（枠と宣言は独立。確定仕様7）。
  int? get _declaredLiveMinutes {
    if (!widget.task.predictionDeclared) return null;
    if (widget.task.sourceType == TaskSourceType.manual &&
        !widget.task.isCompleted) {
      final s = _currentStart;
      final e = _currentEnd;
      if (s != null && e != null) {
        final m = e.difference(s).inMinutes;
        if (m > 0) return m.clamp(1, 24 * 60);
      }
    }
    return widget.task.estimatedMinutes ?? 0;
  }

  int get _liveRewardYen {
    final calc = widget.calcReward;
    if (calc != null) return calc(_plannedLiveMinutes);
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
    _titleCtrl.dispose();
    _actualMinutesCtrl.dispose();
    _actualMinutesFocus.dispose();
    super.dispose();
  }

  /// スタートボタン：タイマー開始処理はこのシートでは行わず、
  /// 結果を返して閉じるだけにする（呼び出し側が安定した context で
  /// `TimerLockLauncher.openForStart` を呼ぶ）。
  void _onTapStartTimer() {
    Navigator.of(context).pop(TaskSheetResult.startTimer);
  }

  /// ポモドーロボタン：同様に結果を返して閉じるだけにする
  /// （呼び出し側が `TimerLockLauncher.openForPomodoro` を呼ぶ）。
  void _onTapStartPomodoro() {
    Navigator.of(context).pop(TaskSheetResult.startPomodoro);
  }

  /// 歯車：シートは閉じずにポモドーロ設定画面を上に重ねて開く。
  void _onTapPomodoroSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const PomodoroSettingsScreen(),
      ),
    );
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
    final newEnd = _currentEnd ??
        picked.add(Duration(minutes: widget.defaultDurationMinutes));
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
    final newStart = _currentStart ??
        picked.subtract(Duration(minutes: widget.defaultDurationMinutes));
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

  /// 編集内容（タイトル・象限・時刻）＋進捗（実績分）を一括保存する中核処理。
  /// pop も SnackBar も行わず、成功/失敗のみ返す（呼び出し側で出し分け）。
  Future<bool> _persistEdits() async {
    final cb = widget.onSaveEdits;
    if (cb == null) return true;
    final title =
        _titleCtrl.text.trim().isEmpty ? widget.task.title : _titleCtrl.text.trim();
    final actual = int.tryParse(_actualMinutesCtrl.text.trim()) ?? 0;
    setState(() => _isSavingEdits = true);
    try {
      return await cb(
        title: title,
        quadrant: _currentQuadrant,
        start: _currentStart,
        end: _currentEnd,
        predictedMinutes: _plannedLiveMinutes,
        actualMinutes: actual,
      );
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
      final ok = await _persistEdits();
      if (!mounted) return false;
      if (!ok) {
        showAppSnackBar(context, const SnackBar(content: Text('保存に失敗しました')));
        return false; // 失敗時はシートを開いたまま
      }
      return true;
    }
    return result == 'discard';
  }

  Future<void> _onTapRevert() async {
    final cb = widget.onRevert;
    if (cb == null) return;
    final ok = await cb();
    if (!mounted) return;
    if (ok) {
      // 実績入力を再操作できるように、完了フラグだけ戻す。
      setState(() {
        _isCompleted = false;
      });
    }
  }

  /// 「保存」ボタン：編集内容（タイトル・象限・時刻）＋進捗（実績分）を一括保存し、
  /// 成功時のみシートを閉じる。失敗時はシートを開いたまま再操作できる。
  Future<void> _onTapSave() async {
    if (widget.onSaveEdits == null) return;
    final ok = await _persistEdits();
    if (!mounted) return;
    if (!ok) {
      showAppSnackBar(context, const SnackBar(content: Text('保存に失敗しました')));
      return;
    }
    showAppSnackBar(
      context,
      const SnackBar(content: Text('保存しました')),
      blocking: false,
    );
    Navigator.of(context).pop();
  }

  Future<void> _onTapComplete() async {
    final fieldText = _actualMinutesCtrl.text.trim();
    final fieldMinutes = int.tryParse(fieldText);
    final fieldHasValue = fieldMinutes != null && fieldMinutes > 0;

    if (!fieldHasValue) {
      showAppSnackBar(
        context,
        const SnackBar(content: Text('実績時間を入力してください')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    // 宣言済みなら宣言値を、未宣言なら 0 を渡す（0 は統計から自動除外。確定仕様9）。
    await widget.onComplete(
      predictedMinutes: _declaredLiveMinutes ?? 0,
      actualMinutes: fieldMinutes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final liveMinutes = _plannedLiveMinutes;
    final predictedLabel = liveMinutes > 0 ? '$liveMinutes分' : '—';
    final declared = _declaredLiveMinutes;
    final declaredLabel = declared == null ? '未宣言' : '$declared分';

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
          controller: widget.scrollController,
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
              // 報酬カード（完了済みは実績、未完了はライブ更新の見込み）
              const SizedBox(height: 12),
              _isCompleted
                  ? _CompletedSummaryCard(task: widget.task)
                  : _RewardCard(
                      predictedLabel: predictedLabel,
                      declaredLabel: declaredLabel,
                      expectedRewardYen: _liveRewardYen,
                    ),
              const SizedBox(height: 16),
              _StartAndActualRow(
                isCompleted: _isCompleted,
                onTapStart: _onTapStartTimer,
                onTapPomodoro: _onTapStartPomodoro,
                onTapPomodoroSettings: _onTapPomodoroSettings,
                controller: _actualMinutesCtrl,
                focusNode: _actualMinutesFocus,
              ),
              const SizedBox(height: 16),
              _CompleteOrRevertRow(
                isCompleted: _isCompleted,
                onComplete: _onTapComplete,
                onSave: (widget.onSaveEdits == null || _isSavingEdits)
                    ? null
                    : _onTapSave,
                onRevert: widget.onRevert == null ? null : _onTapRevert,
              ),
              _ActionButtonsRow(
                onEdit: widget.onEdit == null ? null : () {
                  Navigator.of(context).pop();
                  widget.onEdit!();
                },
                onDuplicate: widget.onDuplicate == null ? null : () {
                  Navigator.of(context).pop();
                  widget.onDuplicate!();
                },
                onDelete: widget.onDelete == null ? null : () {
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
  const _RewardCard({
    required this.predictedLabel,
    required this.declaredLabel,
    required this.expectedRewardYen,
  });

  final String predictedLabel;
  final String declaredLabel;
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
              Icon(Icons.flag_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                '予測宣言：$declaredLabel',
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

/// 完了済みタスクの実績カード：実際に加算された金額と、このタスクの予測精度を表示する。
class _CompletedSummaryCard extends StatelessWidget {
  const _CompletedSummaryCard({required this.task});

  final CalendarTask task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final rewardYen = task.completedRewardYen ?? task.rewardYen;
    final predicted = task.predictedMinutes;
    final actual = task.actualMinutes;
    String? accuracyLabel;
    if (predicted != null && predicted > 0 && actual != null) {
      // 分を主役に表示（確定仕様14）。%はクランプ済みの誤差から算出。
      final diff = actual - predicted;
      final percent = (PredictionAccuracyConfig.errorFor(
                predictedMinutes: predicted,
                actualMinutes: actual,
              ) *
              100)
          .round();
      accuracyLabel =
          '${diff >= 0 ? '+' : ''}$diff分（${percent >= 0 ? '+' : ''}$percent%）'
          '　予測$predicted分→実績$actual分';
    }
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
              Icon(Icons.paid_outlined, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '獲得済み金額',
                  style: text.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
                ),
              ),
              Text(
                '¥${_formatYen(rewardYen)}',
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          if (accuracyLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(Icons.schedule, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    accuracyLabel,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
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

class _StartAndActualRow extends StatelessWidget {
  const _StartAndActualRow({
    required this.isCompleted,
    required this.onTapStart,
    required this.onTapPomodoro,
    required this.onTapPomodoroSettings,
    required this.controller,
    required this.focusNode,
  });

  final bool isCompleted;
  final VoidCallback onTapStart;
  final VoidCallback onTapPomodoro;
  final VoidCallback onTapPomodoroSettings;
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return IgnorePointer(
      ignoring: isCompleted,
      child: Opacity(
        opacity: isCompleted ? 0.4 : 1.0,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              // 二分割スタートボタン：左＝通常タイマー、右＝ポモドーロ。
              // 押すとシートを閉じてロック画面を起動する
              // （タイマー本体の開始・計測はロック画面側で行う）。
              child: SplitStartButton(
                onTapStart: onTapStart,
                onTapPomodoro: onTapPomodoro,
                onTapSettings: onTapPomodoroSettings,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            // 「現状」ラベル＋入力欄をボタンの高さ内に2行で収める
            // （ラベル上端はボタン上端に揃う）。
            SizedBox(
              height: _kStartButtonHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('現状', style: text.labelLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
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
                ],
              ),
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
                  label: const Text('詳細'),
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
