import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/economy/providers/economy_providers.dart';
import 'package:task_manager/features/roulette/model/roulette_outcome.dart';
import 'package:task_manager/features/roulette/providers/roulette_providers.dart';
import 'package:task_manager/features/todo/providers/todo_providers.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/screens/task_completion_screen.dart';
import 'package:task_manager/theme/app_tokens.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/utils/center_flash.dart';
import 'package:task_manager/widgets/draggable_detail_sheet.dart';
import 'package:task_manager/widgets/task_detail/quadrant_selector.dart';

/// 大型一体型タイマーボタンの高さ。「現状」列もこの高さ内に収める。
const double _kTimerButtonHeight = 112;

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

Future<void> showTodoTaskDetailSheet({
  required BuildContext context,
  required CalendarTask task,
}) {
  return showDraggableDetailSheet<void>(
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
  late int _estimatedMinutes;
  late Quadrant _quadrant;

  // タイマー
  Stopwatch? _stopwatch;
  Timer? _ticker;
  int _baselineMinutes = 0;
  bool _needsBaselineCapture = true;

  bool _isCompleting = false;

  bool get _isDirty {
    if (_titleCtrl.text.trim() != widget.task.title) return true;
    if (_descCtrl.text.trim() != (widget.task.description ?? '')) return true;
    if (_urgency != widget.task.urgency) return true;
    if (_importance != widget.task.importance) return true;
    final defaultMinutes =
        ref.read(userSettingsProvider).settings.defaultTodoEstimatedMinutes;
    if (_estimatedMinutes != (widget.task.estimatedMinutes ?? defaultMinutes)) {
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
    _estimatedMinutes = widget.task.estimatedMinutes ??
        ref.read(userSettingsProvider).settings.defaultTodoEstimatedMinutes;
    _quadrant = QuadrantX.from(urgency: _urgency, importance: _importance);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _actualMinutesCtrl.dispose();
    _actualMinutesFocus.dispose();
    super.dispose();
  }

  // ── タイマー ────────────────────────────────────────

  void _writeElapsedToField() {
    final elapsedSec = _stopwatch?.elapsed.inSeconds ?? 0;
    final added = elapsedSec ~/ 60;
    _actualMinutesCtrl.text = (_baselineMinutes + added).toString();
  }

  String _elapsedLabel() {
    final d = _stopwatch?.elapsed ?? Duration.zero;
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _toggleTimer() {
    if (_stopwatch?.isRunning ?? false) {
      _stopwatch!.stop();
      _ticker?.cancel();
      _ticker = null;
      _writeElapsedToField();
    } else {
      if (_needsBaselineCapture) {
        _baselineMinutes = int.tryParse(_actualMinutesCtrl.text.trim()) ?? 0;
        _needsBaselineCapture = false;
      }
      _stopwatch ??= Stopwatch();
      _stopwatch!.start();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      // スタート押下時に画面中央へ「スタート！」を一瞬表示してやる気を高める。
      if (mounted) showCenterFlash(context, 'スタート！');
    }
    if (mounted) setState(() {});
  }

  void _resetTimer() {
    _ticker?.cancel();
    _ticker = null;
    _stopwatch?.stop();
    _stopwatch?.reset();
    _needsBaselineCapture = true;
    if (mounted) setState(() {});
  }

  void _showTimerHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('タイマーの使い方'),
        content: const SingleChildScrollView(
          child: Text(
            '・一時停止すると、計測した時間が「現状」へ自動で追加されます。\n'
            '・「現状」の値は手動で書き換えられます。\n'
            '・リセットしても「現状」の値は保持されます。',
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

  // ── 保存 ────────────────────────────────────────────

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    // description: '' を渡すと copyWith 内で `'' ?? this.description` → '' になるので空文字クリア可能
    final updated = widget.task.copyWith(
      title: title,
      urgency: _urgency,
      importance: _importance,
      estimatedMinutes: _estimatedMinutes,
      description: _descCtrl.text.trim(),
    );
    await ref.read(todoRepositoryProvider).upsert(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ── 完了 ────────────────────────────────────────────

  Future<void> _onTapComplete() async {
    if (_isCompleting) return;

    if (_stopwatch?.isRunning ?? false) {
      _stopwatch!.stop();
      _ticker?.cancel();
      _ticker = null;
      _writeElapsedToField();
      if (mounted) setState(() {});
    }

    final fieldText = _actualMinutesCtrl.text.trim();
    final fieldMinutes = int.tryParse(fieldText);
    final hasActual = fieldMinutes != null && fieldMinutes > 0;

    final settings = ref.read(userSettingsProvider).settings;
    final minutesForReward = hasActual ? fieldMinutes : _estimatedMinutes;
    final reward = settings.hourlyRate > 0
        ? (settings.hourlyRate * minutesForReward / 60).round()
        : widget.task.rewardYen;

    if (!hasActual) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('時間ログなしで完了しますか？'),
          content: Text(
            '「現状」の入力がありません。'
            '入力すると予測精度の計測ができます。\n'
            '完了すると ¥$reward が付与されカレンダーに記録されます。',
          ),
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
    } else {
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
    }

    if (!mounted) return;
    setState(() => _isCompleting = true);

    // 1. 編集内容を先に保存（タイトル・description・象限・所要時間）
    final title = _titleCtrl.text.trim().isNotEmpty
        ? _titleCtrl.text.trim()
        : widget.task.title;
    try {
      final updated = widget.task.copyWith(
        title: title,
        urgency: _urgency,
        importance: _importance,
        estimatedMinutes: _estimatedMinutes,
        description: _descCtrl.text.trim(),
      );
      await ref.read(todoRepositoryProvider).upsert(updated);
    } catch (e) {
      if (mounted) {
        setState(() => _isCompleting = false);
        showAppSnackBar(context, SnackBar(content: Text('保存エラー: $e')));
      }
      return;
    }

    // 2. カレンダーイベントに変換（end=now, start=now-duration）
    final now = DateTime.now();
    final actual = hasActual ? fieldMinutes : null;
    final durationMinutes = actual ?? _estimatedMinutes;
    final start = now.subtract(Duration(minutes: durationMinutes));
    try {
      await ref.read(todoRepositoryProvider).convertToCalendarEvent(
        taskId: widget.task.id,
        start: start,
        end: now,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isCompleting = false);
        showAppSnackBar(context, SnackBar(content: Text('カレンダー変換エラー: $e')));
      }
      return;
    }

    // 3. 報酬付与
    try {
      final result = await ref.read(economyRepositoryProvider).completeTask(
        taskId: widget.task.id,
        title: title,
        rewardYen: reward,
        predictedMinutes: _estimatedMinutes,
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
            predictedMinutes: _estimatedMinutes,
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
      final id = await ref.read(todoRepositoryProvider).createTodo(
        title: '$titleのコピー',
        urgency: _urgency,
        importance: _importance,
        estimatedMinutes: _estimatedMinutes,
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

  void _adjustMinutes(int delta) {
    setState(() {
      _estimatedMinutes = (_estimatedMinutes + delta).clamp(5, 600);
      _quadrant = QuadrantX.from(urgency: _urgency, importance: _importance);
    });
  }

  String _formatMinutes(int m) {
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
    final running = _stopwatch?.isRunning ?? false;
    final canReset = !running && (_stopwatch?.elapsed.inSeconds ?? 0) > 0;

    // 報酬プレビュー
    final settings = ref.read(userSettingsProvider).settings;
    final rewardYen = settings.hourlyRate > 0
        ? (settings.hourlyRate * _estimatedMinutes / 60).round()
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

              // タイマー＋実績
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    // 大型の一体型タイマーボタン：中に経過時間を大きく表示。
                    // タップで開始/一時停止をトグル。状態は ▶/⏸ アイコンと背景色で表す。
                    // ヘルプ（左上）とリセット（右上）はボタンの隅に重ねて縦空間を節約。
                    child: Stack(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: _kTimerButtonHeight,
                          child: FilledButton(
                            onPressed: _toggleTimer,
                            style: FilledButton.styleFrom(
                              backgroundColor: running
                                  ? scheme.primaryContainer
                                  : scheme.secondaryContainer,
                              foregroundColor: running
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSecondaryContainer,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  running
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 32,
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _elapsedLabel(),
                                      style: text.displayMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // ヘルプ（隅に小さく）
                        Positioned(
                          top: 4,
                          left: 4,
                          child: IconButton(
                            onPressed: _showTimerHelp,
                            icon: const Icon(Icons.help_outline),
                            tooltip: 'タイマーの使い方',
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            color: running
                                ? scheme.onPrimaryContainer
                                : scheme.onSecondaryContainer,
                          ),
                        ),
                        // リセット（隅に小さく）：一時停止中かつ経過 > 0 のみ有効。
                        Positioned(
                          top: 4,
                          right: 4,
                          child: IconButton(
                            onPressed: canReset ? _resetTimer : null,
                            icon: const Icon(Icons.refresh_rounded),
                            tooltip: 'リセット',
                            iconSize: 20,
                            visualDensity: VisualDensity.compact,
                            color: running
                                ? scheme.onPrimaryContainer
                                : scheme.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  // 「現状」ラベル＋入力欄をタイマーの高さ内に2行で収める
                  // （ラベル上端はタイマー上端に揃う）。
                  SizedBox(
                    height: _kTimerButtonHeight,
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
