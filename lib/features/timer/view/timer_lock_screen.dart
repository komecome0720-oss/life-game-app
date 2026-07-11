import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/features/economy/providers/economy_providers.dart';
import 'package:task_manager/features/pomodoro/providers/pomodoro_day_providers.dart';
import 'package:task_manager/features/timer/model/active_timer.dart';
import 'package:task_manager/features/timer/providers/timer_providers.dart';
import 'package:task_manager/features/timer/view/timer_lock_launcher.dart';
import 'package:task_manager/features/timer/viewmodel/timer_actions.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/screens/task_completion_screen.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/utils/center_flash.dart';
import 'package:task_manager/widgets/message_guard.dart';

/// タイマー計測中のフルスクリーンロック画面。
///
/// ToDo・カレンダー予定の両方に対応する唯一のロック画面。計測中(running)は
/// ✕・OSの戻る/スワイプバックのいずれも閉じられず（PopScope(canPop: false)）、
/// 「タイマー動作中は閉じられません」とメッセージを表示する。
/// 一時停止中のみ ✕ で閉じられる。
///
/// 表示は常に `activeTimerStreamProvider` の最新値を反映する。自画面の操作
/// （✕・完了）による削除中は `_closing` フラグで最後の値を描画し続け、
/// 別端末からの削除等・自分起因でない null は自動 pop する。
class TimerLockScreen extends ConsumerStatefulWidget {
  const TimerLockScreen({
    super.key,
    required this.initialTimer,
    required this.initialTask,
    this.showStartFlash = false,
    this.quickStart = false,
  });

  /// 起動時点の ActiveTimer（以後は stream の値で更新される）。
  final ActiveTimer initialTimer;

  /// 対象タスク。削除済み復元時は null。
  final CalendarTask? initialTask;

  /// スタート起点で開いたときのみ true（「スタート！」演出用）。
  final bool showStartFlash;

  /// クイックスタート（FAB長押し）で作られたタスクかどうか。
  /// true の間は名前欄が空欄＋プレースホルダー表示、見込み欄が編集可になる。
  final bool quickStart;

  @override
  ConsumerState<TimerLockScreen> createState() => _TimerLockScreenState();
}

class _TimerLockScreenState extends ConsumerState<TimerLockScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _actualMinutesCtrl;
  final FocusNode _actualMinutesFocus = FocusNode();

  // タスク名編集用。
  late final TextEditingController _titleController;
  final FocusNode _titleFocus = FocusNode();
  bool _titleCommitting = false;

  // クイックスタートのときのみ編集可の「見込み」欄。
  late final TextEditingController _predictedController;
  final FocusNode _predictedFocus = FocusNode();
  bool _predictedCommitting = false;

  // クイックスタートで名前欄をユーザーが確定入力するまでは、
  // 空欄プレースホルダーを毎秒 setState・stream 更新で潰さないためのフラグ。
  bool _nameCommittedByUser = false;

  final GlobalKey _closeButtonKey = GlobalKey();
  Timer? _ticker;

  // 自画面の操作（✕・完了）でドキュメントを消す最中は、stream の null を
  // 「他端末からの削除」と誤認して自動 pop しないようにするためのフラグ。
  bool _closing = false;
  bool _isSaving = false;
  bool _isCompleting = false;

  late ActiveTimer _lastTimer;
  CalendarTask? _task;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastTimer = widget.initialTimer;
    _task = widget.initialTask;
    _actualMinutesCtrl =
        TextEditingController(text: (_task?.actualMinutes ?? 0).toString());
    _titleController =
        TextEditingController(text: widget.quickStart ? '' : _displayTaskTitle);
    _titleFocus.addListener(() {
      if (!_titleFocus.hasFocus) _commitTitle();
    });
    _predictedController =
        TextEditingController(text: _lastTimer.predictedMinutes.toString());
    _predictedFocus.addListener(() {
      if (!_predictedFocus.hasFocus) _commitPredicted();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (widget.showStartFlash) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showCenterFlash(context, 'スタート！');
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _actualMinutesCtrl.dispose();
    _actualMinutesFocus.dispose();
    _titleController.dispose();
    _titleFocus.dispose();
    _predictedController.dispose();
    _predictedFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // バックグラウンド復帰後、次のtickを待たずに経過を即時反映する。
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  String get _displayTaskTitle => _task?.title ?? _lastTimer.taskTitle;

  int get _currentActualMinutes =>
      int.tryParse(_actualMinutesCtrl.text.trim()) ?? 0;

  String _elapsedLabel(int elapsedSec) {
    final d = Duration(seconds: elapsedSec);
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// タスク名の確定処理：フォーカスを失ったとき／キーボード完了時に呼ぶ。
  /// クイックスタートのタスクで空欄のまま確定した場合は、裏のタイトルを
  /// 変更せず欄も空のまま保持する（確定仕様3）。
  Future<void> _commitTitle() async {
    if (_titleCommitting) return;
    final newTitle = _titleController.text.trim();
    final currentTitle = _displayTaskTitle;
    if (newTitle.isEmpty && widget.quickStart) {
      return;
    }
    if (newTitle.isEmpty || newTitle == currentTitle) {
      _titleController.text = currentTitle;
      return;
    }
    _titleCommitting = true;
    try {
      final task = _task;
      if (task != null) {
        await ref.read(calendarTaskSyncRepositoryProvider).updateTask(
              taskId: _lastTimer.taskId,
              title: newTitle,
            );
      }
      await ref.read(activeTimerRepositoryProvider).updateTaskTitle(newTitle);
      if (!mounted) return;
      setState(() {
        _task = _task?.copyWith(title: newTitle);
        _lastTimer = _lastTimer.copyWith(taskTitle: newTitle);
        _nameCommittedByUser = true;
      });
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          const SnackBar(content: Text('タスク名を保存できませんでした')),
        );
      }
      _titleController.text = currentTitle;
    } finally {
      _titleCommitting = false;
    }
  }

  /// 「見込み」の確定処理（クイックスタートのタスクのみ編集可）。
  Future<void> _commitPredicted() async {
    if (_predictedCommitting) return;
    final raw = int.tryParse(_predictedController.text.trim()) ?? 0;
    final parsed = raw < 0 ? 0 : raw;
    final current = _lastTimer.predictedMinutes;
    if (parsed == current) {
      _predictedController.text = current.toString();
      return;
    }
    _predictedCommitting = true;
    try {
      await ref
          .read(activeTimerRepositoryProvider)
          .updatePredictedMinutes(parsed);
      if (!mounted) return;
      setState(() {
        _lastTimer = _lastTimer.copyWith(predictedMinutes: parsed);
      });
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          const SnackBar(content: Text('見込みを保存できませんでした')),
        );
      }
      _predictedController.text = current.toString();
    } finally {
      _predictedCommitting = false;
    }
  }

  /// 名前欄・見込み欄の未確定編集をフラッシュする。一時停止・保存・✕・完了の
  /// 各操作の直前に呼ぶ（ボタンタップはフォーカスを奪わないため、確定処理が
  /// 走らないまま計算に進んでしまう不整合を防ぐ。ポモドーロ画面の
  /// `_flushPendingEdits` を踏襲）。
  Future<void> _flushPendingEdits() async {
    FocusScope.of(context).unfocus();
    if (_titleController.text.trim() != _displayTaskTitle) {
      await _commitTitle();
    }
    if (widget.quickStart) {
      await _commitPredicted();
    }
  }

  Future<void> _togglePauseResume(ActiveTimer timer) async {
    await _flushPendingEdits();
    if (!mounted) return;
    final repo = ref.read(activeTimerRepositoryProvider);
    if (timer.isRunning) {
      await repo.pause(timer);
    } else {
      await repo.resume(timer);
    }
  }

  /// 保存：現状欄 + 経過分(秒切り捨て) を合算して timer_actions.saveProgress へ。
  /// 成功したら resetToZero し、現状欄へ合計を反映する。
  Future<void> _onTapSave(ActiveTimer timer) async {
    if (_isSaving) return;
    await _flushPendingEdits();
    if (!mounted) return;
    final task = _task;
    if (task == null) return;
    setState(() => _isSaving = true);
    final current = _lastTimer;
    final elapsedSec = current.elapsedSeconds(DateTime.now());
    final total = _currentActualMinutes + elapsedSec ~/ 60;
    final ok = await ref.read(timerActionsProvider).saveProgress(
          taskId: current.taskId,
          predictedMinutes: current.predictedMinutes,
          actualMinutes: total,
        );
    if (!mounted) return;
    if (ok) {
      unawaited(
        ref
            .read(economyRepositoryProvider)
            .addWorkSeconds(elapsedSec)
            .catchError((Object _) {}),
      );
      await ref.read(activeTimerRepositoryProvider).resetToZero();
      if (!mounted) return;
      _actualMinutesCtrl.text = total.toString();
      setState(() => _isSaving = false);
      showAppSnackBar(context, const SnackBar(content: Text('保存しました')));
    } else {
      setState(() => _isSaving = false);
      showAppSnackBar(context, const SnackBar(content: Text('保存に失敗しました')));
    }
  }

  /// ✕（一時停止中のみ閉じられる）：経過分0なら破棄して即閉じ。>0なら保存と同じ処理をして閉じる。
  /// 計測中に押された場合は閉じずにメッセージを表示する。
  Future<void> _onTapClose(ActiveTimer timer) async {
    if (timer.isRunning) {
      showAnchoredFlash(
        context,
        'タイマー動作中は閉じられません',
        anchorKey: _closeButtonKey,
      );
      return;
    }
    await _flushPendingEdits();
    if (!mounted) return;
    final current = _lastTimer;
    final elapsedSec = current.elapsedSeconds(DateTime.now());
    final addedMinutes = elapsedSec ~/ 60;
    if (addedMinutes == 0) {
      _closing = true;
      await ref.read(activeTimerRepositoryProvider).clear();
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final task = _task;
    if (task == null) {
      await _confirmDiscardAndClose();
      return;
    }

    final total = _currentActualMinutes + addedMinutes;
    final ok = await ref.read(timerActionsProvider).saveProgress(
          taskId: current.taskId,
          predictedMinutes: current.predictedMinutes,
          actualMinutes: total,
        );
    if (!mounted) return;
    if (ok) {
      unawaited(
        ref
            .read(economyRepositoryProvider)
            .addWorkSeconds(elapsedSec)
            .catchError((Object _) {}),
      );
      _closing = true;
      await ref.read(activeTimerRepositoryProvider).clear();
      if (mounted) Navigator.of(context).pop();
    } else {
      await _confirmDiscardAndClose();
    }
  }

  Future<void> _confirmDiscardAndClose() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存できませんでした'),
        content: const Text('計測を破棄して閉じますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('破棄して閉じる'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    _closing = true;
    await ref.read(activeTimerRepositoryProvider).clear();
    if (mounted) Navigator.of(context).pop();
  }

  /// 完了：running なら先に pause 相当。実績合計が0以下なら完了できない（実績必須化）。
  Future<void> _onTapComplete(ActiveTimer timer) async {
    if (_isCompleting) return;
    await _flushPendingEdits();
    if (!mounted) return;
    final task = _task;
    if (task == null) {
      showAppSnackBar(context, const SnackBar(content: Text('タスクが見つかりませんでした')));
      return;
    }

    final current = _lastTimer;
    final elapsedSec = current.elapsedSeconds(DateTime.now());
    final addedMinutes = elapsedSec ~/ 60;
    final total = _currentActualMinutes + addedMinutes;
    if (total <= 0) {
      showAppSnackBar(context, const SnackBar(content: Text('実績時間を入力してください')));
      return;
    }
    final actualMinutes = total;

    // 確認ダイアログ：ToDoは常に確認する（既存の各シートの挙動を踏襲）。
    final bool confirmed;
    if (task.isTodo) {
      confirmed = await _confirmComplete(
        title: '完了しますか？',
        content: '完了として記録します。',
      ) ==
          true;
    } else {
      confirmed = true;
    }
    if (!confirmed || !mounted) return;

    setState(() => _isCompleting = true);
    final outcome = await ref.read(timerActionsProvider).complete(
          task: task,
          predictedMinutes: current.predictedMinutes,
          actualMinutes: actualMinutes,
        );
    if (!mounted) return;
    if (outcome == null) {
      setState(() => _isCompleting = false);
      showAppSnackBar(context, const SnackBar(content: Text('完了処理に失敗しました')));
      return;
    }

    unawaited(
      ref
          .read(economyRepositoryProvider)
          .addWorkSeconds(elapsedSec)
          .catchError((Object _) {}),
    );
    _closing = true;
    await ref.read(activeTimerRepositoryProvider).clear();
    if (!mounted) return;
    unawaited(
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => TaskCompletionScreen(
            taskTitle: outcome.taskTitle,
            rewardYen: outcome.rewardYen,
            balanceBeforeYen: outcome.balanceBeforeYen,
            balanceAfterYen: outcome.balanceAfterYen,
            outcome: outcome.outcome,
            cumulativeTaskCountBefore: outcome.cumulativeTaskCountBefore,
            cumulativeTaskCountAfter: outcome.cumulativeTaskCountAfter,
            predictedMinutes: outcome.predictedMinutes,
            actualMinutes: outcome.actualMinutes,
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmComplete({
    required String title,
    required String content,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
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
  }

  @override
  Widget build(BuildContext context) {
    // ログアウトしたらロック画面を後始末する。
    ref.listen<AsyncValue<Object?>>(authStateProvider, (prev, next) {
      final user = next.asData?.value;
      if (user == null && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });

    // 名前欄・見込み欄のコントローラは、非フォーカス時のみ最新値へ同期する
    // （毎秒 setState・stream 更新で入力中のテキストを潰さないため、
    // build内では直接書き換えない。ポモドーロ画面の既存パターンを踏襲）。
    ref.listen<AsyncValue<ActiveTimer?>>(activeTimerStreamProvider, (prev, next) {
      final timer = next.asData?.value;
      if (timer == null) return;
      _lastTimer = timer;
      final task = _task;
      if (task != null &&
          timer.taskTitle.isNotEmpty &&
          task.title != timer.taskTitle) {
        _task = task.copyWith(title: timer.taskTitle);
      }
      if (!_titleCommitting &&
          !_titleFocus.hasFocus &&
          !(widget.quickStart && !_nameCommittedByUser) &&
          _titleController.text != _displayTaskTitle) {
        _titleController.text = _displayTaskTitle;
      }
      if (widget.quickStart &&
          !_predictedCommitting &&
          !_predictedFocus.hasFocus &&
          _predictedController.text != timer.predictedMinutes.toString()) {
        _predictedController.text = timer.predictedMinutes.toString();
      }
    });

    final asyncTimer = ref.watch(activeTimerStreamProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final timer = asyncTimer.asData?.value ?? _lastTimer;
        // running中は _onTapClose 内でメッセージ表示のみ行い閉じない。
        await _onTapClose(timer);
      },
      child: Scaffold(
        body: MessageGuard(
          child: asyncTimer.when(
            data: (timer) {
              if (timer == null) {
                if (!_closing) {
                  // 自分起因でなく消えた（別端末で完了等）→ 自動 pop。
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) Navigator.of(context).maybePop();
                  });
                }
                timer = _lastTimer;
              } else {
                _lastTimer = timer;
              }
              return _buildBody(context, timer);
            },
            loading: () => _buildBody(context, _lastTimer),
            error: (_, _) => _buildBody(context, _lastTimer),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ActiveTimer timer) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final running = timer.isRunning;
    final elapsedSec = timer.elapsedSeconds(DateTime.now());

    // 「本日 X時間Y分」表示用（本日累計＋進行中の経過秒。
    // todayEarningsStreamProvider は main.dart で常時listenされているメモリ値を参照する）。
    final earningsWorkSeconds =
        ref.watch(todayEarningsStreamProvider).value?.workSeconds ?? 0;
    final totalWorkSeconds = earningsWorkSeconds + elapsedSec;
    final todayWorkHours = totalWorkSeconds ~/ 3600;
    final todayWorkMinutes = (totalWorkSeconds % 3600) ~/ 60;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            key: _closeButtonKey,
                            onPressed: () => _onTapClose(timer),
                            icon: const Icon(Icons.close),
                            tooltip: '閉じる',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _titleController,
                        focusNode: _titleFocus,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _commitTitle(),
                        style: text.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                        decoration: InputDecoration(
                          filled: true,
                          isDense: true,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          hintText:
                              widget.quickStart ? kQuickStartDefaultTitle : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '本日 $todayWorkHours時間$todayWorkMinutes分',
                        style:
                            text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const Spacer(),
                      Center(
                        child: Text(
                          _elapsedLabel(elapsedSec),
                          style: text.displayLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('見込み', style: text.labelLarge),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 140,
                                child: widget.quickStart
                                    ? TextField(
                                        controller: _predictedController,
                                        focusNode: _predictedFocus,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                                decimal: false),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                          LengthLimitingTextInputFormatter(4),
                                        ],
                                        textAlign: TextAlign.center,
                                        textInputAction: TextInputAction.done,
                                        onSubmitted: (_) => _commitPredicted(),
                                        style: text.titleLarge?.copyWith(
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          suffixText: '分',
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                        ),
                                      )
                                    : Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          border:
                                              Border.all(color: scheme.outline),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${timer.predictedMinutes}分',
                                          textAlign: TextAlign.center,
                                          style: text.titleLarge?.copyWith(
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('現状', style: text.labelLarge),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 140,
                                child: TextField(
                                  controller: _actualMinutesCtrl,
                                  focusNode: _actualMinutesFocus,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: false),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(4),
                                  ],
                                  textAlign: TextAlign.center,
                                  style: text.titleLarge?.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    suffixText: '分',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () => _togglePauseResume(timer),
                        icon: Icon(running
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded),
                        label: Text(running ? '一時停止' : '再開'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed:
                                  _isSaving ? null : () => _onTapSave(timer),
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('保存',
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isCompleting
                                  ? null
                                  : () => _onTapComplete(timer),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('完了',
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
