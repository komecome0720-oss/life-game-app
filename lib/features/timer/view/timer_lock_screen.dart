import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';
import 'package:task_manager/features/timer/model/active_timer.dart';
import 'package:task_manager/features/timer/providers/timer_providers.dart';
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
  });

  /// 起動時点の ActiveTimer（以後は stream の値で更新される）。
  final ActiveTimer initialTimer;

  /// 対象タスク。削除済み復元時は null。
  final CalendarTask? initialTask;

  /// スタート起点で開いたときのみ true（「スタート！」演出用）。
  final bool showStartFlash;

  @override
  ConsumerState<TimerLockScreen> createState() => _TimerLockScreenState();
}

class _TimerLockScreenState extends ConsumerState<TimerLockScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _actualMinutesCtrl;
  final FocusNode _actualMinutesFocus = FocusNode();
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // バックグラウンド復帰後、次のtickを待たずに経過を即時反映する。
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  int get _currentActualMinutes =>
      int.tryParse(_actualMinutesCtrl.text.trim()) ?? 0;

  String _elapsedLabel(int elapsedSec) {
    final d = Duration(seconds: elapsedSec);
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _togglePauseResume(ActiveTimer timer) async {
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
    final task = _task;
    if (task == null) return;
    setState(() => _isSaving = true);
    final elapsedSec = timer.elapsedSeconds(DateTime.now());
    final total = _currentActualMinutes + elapsedSec ~/ 60;
    final ok = await ref.read(timerActionsProvider).saveProgress(
          taskId: timer.taskId,
          predictedMinutes: timer.predictedMinutes,
          actualMinutes: total,
        );
    if (!mounted) return;
    if (ok) {
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
    final elapsedSec = timer.elapsedSeconds(DateTime.now());
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
          taskId: timer.taskId,
          predictedMinutes: timer.predictedMinutes,
          actualMinutes: total,
        );
    if (!mounted) return;
    if (ok) {
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

  /// 完了：running なら先に pause 相当。合計0なら actualMinutes=null（ログなし完了）。
  Future<void> _onTapComplete(ActiveTimer timer) async {
    if (_isCompleting) return;
    final task = _task;
    if (task == null) {
      showAppSnackBar(context, const SnackBar(content: Text('タスクが見つかりませんでした')));
      return;
    }

    final elapsedSec = timer.elapsedSeconds(DateTime.now());
    final addedMinutes = elapsedSec ~/ 60;
    final total = _currentActualMinutes + addedMinutes;
    final actualMinutes = total > 0 ? total : null;

    // 確認ダイアログ：カレンダーは合計0のときのみ、ToDoは常に確認する
    // （既存の各シートの挙動を踏襲）。
    final bool confirmed;
    if (task.isTodo) {
      confirmed = await _confirmComplete(
        title: '完了しますか？',
        content: actualMinutes == null ? '時間ログなしで完了します。' : '完了として記録します。',
      ) ==
          true;
    } else if (actualMinutes == null) {
      confirmed = await _confirmComplete(
        title: '時間ログなしで完了しますか？',
        content: '時間予測ログが残りませんがよろしいですか？',
      ) ==
          true;
    } else {
      confirmed = true;
    }
    if (!confirmed || !mounted) return;

    setState(() => _isCompleting = true);
    final outcome = await ref.read(timerActionsProvider).complete(
          task: task,
          predictedMinutes: timer.predictedMinutes,
          actualMinutes: actualMinutes,
        );
    if (!mounted) return;
    if (outcome == null) {
      setState(() => _isCompleting = false);
      showAppSnackBar(context, const SnackBar(content: Text('完了処理に失敗しました')));
      return;
    }

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
    final taskTitle = _task?.title ?? timer.taskTitle;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
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
            Text(
              taskTitle,
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              timer.predictedMinutes > 0 ? '見込時間：${timer.predictedMinutes}分' : '見込時間：—',
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
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
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('現状', style: text.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _actualMinutesCtrl,
                          focusNode: _actualMinutesFocus,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: false),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          textAlign: TextAlign.end,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('分', style: text.bodyLarge),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _togglePauseResume(timer),
              icon: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded),
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
                    onPressed: _isSaving ? null : () => _onTapSave(timer),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('保存', overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isCompleting ? null : () => _onTapComplete(timer),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('完了', overflow: TextOverflow.ellipsis),
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
