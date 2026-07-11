import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/economy/model/reward_calculator.dart';
import 'package:task_manager/features/economy/viewmodel/economy_fast_complete_service.dart';
import 'package:task_manager/features/pomodoro/view/pomodoro_settings_screen.dart';
import 'package:task_manager/features/roulette/model/roulette_outcome.dart';
import 'package:task_manager/features/roulette/providers/roulette_providers.dart';
import 'package:task_manager/features/timer/model/task_sheet_result.dart';
import 'package:task_manager/features/timer/providers/timer_providers.dart';
import 'package:task_manager/features/timer/widgets/split_start_button.dart';
import 'package:task_manager/features/todo/providers/todo_providers.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/screens/task_completion_screen.dart';
import 'package:task_manager/theme/app_tokens.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/draggable_detail_sheet.dart';
import 'package:task_manager/widgets/prediction_chip_sheet.dart';
import 'package:task_manager/widgets/task_detail/quadrant_selector.dart';

/// 大型一体型スタートボタンの高さ。「現状」列もこの高さ内に収める。
const double _kStartButtonHeight = kSplitStartButtonHeight;

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

/// 戻り値が [TaskSheetResult.startTimer] の場合、呼び出し側は安定した context で
/// `TimerLockLauncher.openForStart` を呼んでロック画面を起動する（このシート自身は
/// タイマー開始処理を行わない。詳細は `lib/features/timer/view/timer_lock_launcher.dart`）。
Future<TaskSheetResult?> showTodoTaskDetailSheet({
  required BuildContext context,
  required CalendarTask task,
}) {
  return showDraggableDetailSheet<TaskSheetResult>(
    context: context,
    builder: (context, scrollController) =>
        _TodoDetailBody(task: task, scrollController: scrollController),
  );
}

class _TodoDetailBody extends ConsumerStatefulWidget {
  const _TodoDetailBody({required this.task, this.scrollController});
  final CalendarTask task;
  final ScrollController? scrollController;

  @override
  ConsumerState<_TodoDetailBody> createState() => _TodoDetailBodyState();
}

class _TodoDetailBodyState extends ConsumerState<_TodoDetailBody> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _actualMinutesCtrl;
  final FocusNode _actualMinutesFocus = FocusNode();

  late bool _urgency;
  late bool _importance;

  /// 宣言済み予測（分）。null は未宣言（「未設定（—）」表示から開始）。
  /// ステッパーを明示的に触ると宣言になる（保存時 predictionDeclared: true）。
  int? _estimatedMinutes;
  late Quadrant _quadrant;

  bool _isCompleting = false;

  bool get _isDirty {
    if (_titleCtrl.text.trim() != widget.task.title) return true;
    if (_descCtrl.text.trim() != (widget.task.description ?? '')) return true;
    if (_urgency != widget.task.urgency) return true;
    if (_importance != widget.task.importance) return true;
    if (_estimatedMinutes != declaredPredictedMinutes(widget.task)) {
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.task.title);
    _descCtrl = TextEditingController(text: widget.task.description ?? '');
    _actualMinutesCtrl = TextEditingController();
    final saved = widget.task.actualMinutes;
    if (saved != null && saved > 0) {
      _actualMinutesCtrl.text = saved.toString();
    }
    _urgency = widget.task.urgency;
    _importance = widget.task.importance;
    _estimatedMinutes = declaredPredictedMinutes(widget.task);
    _quadrant = QuadrantX.from(urgency: _urgency, importance: _importance);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _actualMinutesCtrl.dispose();
    _actualMinutesFocus.dispose();
    super.dispose();
  }

  // ── スタート ────────────────────────────────────────

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

  // ── 保存 ────────────────────────────────────────────

  /// 編集内容を反映したタスク。ステッパーを触って宣言した場合は
  /// estimatedMinutes＋predictionDeclared を併せて反映する
  /// （未宣言のままなら元の宣言状態を維持）。
  CalendarTask _editedTask(String title) {
    // description: '' を渡すと copyWith 内で `'' ?? this.description` → '' になるので空文字クリア可能
    return widget.task.copyWith(
      title: title,
      urgency: _urgency,
      importance: _importance,
      estimatedMinutes: _estimatedMinutes,
      predictionDeclared:
          _estimatedMinutes != null ? true : widget.task.predictionDeclared,
      description: _descCtrl.text.trim(),
    );
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final updated = _editedTask(title);
    await ref.read(todoRepositoryProvider).upsert(updated);
    // 作動中タイマーが同タスクなら active_timer.taskTitle も同期する
    // （失敗しても保存全体は失敗扱いにしない＝表示追従用のため個別に握りつぶす）。
    final activeTimer = ref.read(activeTimerStreamProvider).value;
    if (activeTimer != null &&
        activeTimer.taskId == widget.task.id &&
        activeTimer.taskTitle != title) {
      try {
        await ref.read(activeTimerRepositoryProvider).updateTaskTitle(title);
      } catch (_) {
        // no-op: active_timer 側の追従失敗は保存成否に影響させない。
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ── 完了 ────────────────────────────────────────────

  Future<void> _onTapComplete() async {
    if (_isCompleting) return;

    final fieldText = _actualMinutesCtrl.text.trim();
    final fieldMinutes = int.tryParse(fieldText);
    final hasActual = fieldMinutes != null && fieldMinutes > 0;

    if (!hasActual) {
      showAppSnackBar(context, const SnackBar(content: Text('実績時間を入力してください')));
      return;
    }

    final settings = ref.read(userSettingsProvider).settings;
    final minutesForReward = fieldMinutes;
    final reward = settings.taskHourlyRate > 0
        ? rewardYenFor(hourlyRate: settings.taskHourlyRate, minutes: minutesForReward)
        : widget.task.rewardYen;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('完了しますか？'),
        content: Text('¥$reward を獲得し、完了として記録します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('完了する'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    if (!mounted) return;
    setState(() => _isCompleting = true);

    // 1. 編集内容の保存とカレンダー変換を1回の書き込みにまとめる
    final title = _titleCtrl.text.trim().isNotEmpty
        ? _titleCtrl.text.trim()
        : widget.task.title;
    final now = DateTime.now();
    final actual = fieldMinutes;
    final durationMinutes = actual;
    var start = now.subtract(Duration(minutes: durationMinutes));
    final dayStart = DateTime(now.year, now.month, now.day);
    if (start.isBefore(dayStart)) start = dayStart; // 日またぎ丸め（仕様5）
    final updated = _editedTask(title);
    try {
      await ref.read(todoRepositoryProvider).upsertAndConvertToCalendarEvent(
        task: updated,
        start: start,
        end: now,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isCompleting = false);
        showAppSnackBar(context, SnackBar(content: Text('保存エラー: $e')));
      }
      return;
    }

    // 3. 報酬付与
    try {
      final result = await ref
          .read(economyFastCompleteServiceProvider)
          .completeTaskFast(
            taskId: widget.task.id,
            title: title,
            rewardYen: reward,
            // 宣言済みなら宣言値、未宣言なら 0（統計から自動除外。確定仕様9）。
            predictedMinutes: _estimatedMinutes ?? 0,
            actualMinutes: actual,
          );
      if (!result.applied) {
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }

      // 4. ルーレット抽選
      RouletteOutcome? outcome;
      try {
        outcome = await ref.read(rouletteServiceProvider).spin(
          completionId: widget.task.id,
          settings: ref.read(userSettingsProvider).settings,
        );
      } catch (_) {
        outcome = null;
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      unawaited(Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TaskCompletionScreen(
            taskTitle: title,
            rewardYen: reward,
            balanceBeforeYen: result.balanceBeforeYen,
            balanceAfterYen: result.balanceAfterYen,
            outcome: outcome,
            cumulativeTaskCountBefore: result.cumulativeTaskCountBefore,
            cumulativeTaskCountAfter: result.cumulativeTaskCountAfter,
            // 宣言済みなら宣言値、未宣言なら 0（統計から自動除外。確定仕様9）。
            predictedMinutes: _estimatedMinutes ?? 0,
            actualMinutes: actual,
          ),
        ),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _isCompleting = false);
        showAppSnackBar(context, SnackBar(content: Text('完了処理エラー: $e')));
      }
    }
  }

  // ── 複製 ────────────────────────────────────────────

  Future<void> _duplicate() async {
    final title = _titleCtrl.text.trim().isNotEmpty
        ? _titleCtrl.text.trim()
        : widget.task.title;
    final desc = _descCtrl.text.trim();
    try {
      // 複製元の宣言状態を引き継ぐ（未宣言なら null＋false）。
      final id = await ref.read(todoRepositoryProvider).createTodo(
        title: '$titleのコピー',
        urgency: _urgency,
        importance: _importance,
        estimatedMinutes: _estimatedMinutes,
        predictionDeclared: _estimatedMinutes != null,
        orderIndex: widget.task.orderIndex,
        description: desc.isNotEmpty ? desc : null,
      );
      if (id.isNotEmpty && mounted) {
        showAppSnackBar(context, const SnackBar(content: Text('複製しました')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, SnackBar(content: Text('複製に失敗しました: $e')));
      }
    }
  }

  // ── 削除 ────────────────────────────────────────────

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${widget.task.title}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('削除', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(todoMatrixViewModelProvider).delete(widget.task.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ── ステッパー ───────────────────────────────────────

  /// ステッパー操作＝宣言。未宣言（null）から触った場合は 0 起点で加減する。
  void _adjustMinutes(int delta) {
    setState(() {
      _estimatedMinutes = ((_estimatedMinutes ?? 0) + delta).clamp(5, 600);
      _quadrant = QuadrantX.from(urgency: _urgency, importance: _importance);
    });
  }

  String _formatMinutes(int? m) {
    if (m == null) return '未設定（—）';
    if (m < 60) return '$m分';
    if (m % 60 == 0) return '${m ~/ 60}時間';
    return '${m ~/ 60}時間${m % 60}分';
  }

  // ── 未保存ガード ─────────────────────────────────────

  Future<bool> _onWillPop() async {
    if (!_isDirty) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('変更を保存しますか？'),
        content: const Text('編集中の内容が保存されていません。'),
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
      await _save();
      return false; // _save() pops itself
    }
    return result == 'discard';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    // 報酬プレビュー（報酬計算は従来ロジック維持。宣言が無ければ既存の
    // estimatedMinutes にフォールバック。確定仕様16）
    final settings = ref.read(userSettingsProvider).settings;
    final plannedMinutes = _estimatedMinutes ?? widget.task.estimatedMinutes ?? 0;
    final rewardYen = settings.taskHourlyRate > 0 && plannedMinutes > 0
        ? rewardYenFor(hourlyRate: settings.taskHourlyRate, minutes: plannedMinutes)
        : widget.task.rewardYen;

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
              // ヘッダー：種別チップ＋タイトル編集
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'ToDo',
                      style: text.labelSmall?.copyWith(
                        color: scheme.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleCtrl,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                decoration: const InputDecoration(
                  hintText: 'タイトル',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) => setState(() {}),
              ),

              // 予想所要時間ステッパー
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.timelapse, color: scheme.onSurfaceVariant, size: 20),
                  const SizedBox(width: 8),
                  Text('予想所要時間', style: text.labelLarge),
                  const Spacer(),
                  IconButton.outlined(
                    onPressed: () => _adjustMinutes(-15),
                    icon: const Icon(Icons.remove),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatMinutes(_estimatedMinutes),
                    style: text.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: () => _adjustMinutes(15),
                    icon: const Icon(Icons.add),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),

              // 領域セレクター
              const SizedBox(height: 12),
              Text('領域', style: text.labelMedium),
              const SizedBox(height: 8),
              QuadrantSelector(
                selected: _quadrant,
                onSelect: (q) {
                  setState(() {
                    _quadrant = q;
                    _urgency = q.urgency;
                    _importance = q.importance;
                  });
                },
              ),

              // 報酬カード
              const SizedBox(height: 12),
              Container(
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
                        Icon(Icons.timelapse, size: 18, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          '見込時間：${_formatMinutes(_estimatedMinutes)}',
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
                            style: text.bodySmall?.copyWith(
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        Text(
                          '¥$rewardYen',
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // スタート＋実績
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    // 二分割スタートボタン：左＝通常タイマー、右＝ポモドーロ。
                    // 押すとシートを閉じてロック画面を起動する
                    // （タイマー本体の開始・計測はロック画面側で行う）。
                    child: SplitStartButton(
                      onTapStart: _onTapStartTimer,
                      onTapPomodoro: _onTapStartPomodoro,
                      onTapSettings: _onTapPomodoroSettings,
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
                                controller: _actualMinutesCtrl,
                                focusNode: _actualMinutesFocus,
                                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(4),
                                ],
                                textAlign: TextAlign.end,
                                textAlignVertical: TextAlignVertical.center,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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

              // メモ欄
              const SizedBox(height: 16),
              TextField(
                controller: _descCtrl,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'メモ（説明）',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),

              // 完了・保存ボタン
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _isDirty ? _save : null,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('保存', overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isCompleting ? null : _onTapComplete,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('完了', overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),

              // 複製・削除
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _duplicate,
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('複製'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _confirmDelete,
                      icon: Icon(Icons.delete_outline, color: scheme.error),
                      label: Text('削除', style: TextStyle(color: scheme.error)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
