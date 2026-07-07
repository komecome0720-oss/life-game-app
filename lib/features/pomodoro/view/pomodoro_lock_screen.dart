import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_schedule.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_settings.dart';
import 'package:task_manager/features/pomodoro/providers/pomodoro_providers.dart';
import 'package:task_manager/features/timer/model/active_timer.dart';
import 'package:task_manager/features/timer/providers/timer_providers.dart';
import 'package:task_manager/features/timer/viewmodel/timer_actions.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/screens/task_completion_screen.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/utils/center_flash.dart';
import 'package:task_manager/widgets/message_guard.dart';

/// ポモドーロ計測中のフルスクリーンロック画面。
///
/// `TimerLockScreen` の構造を踏襲しつつ、フェーズ（クエスト/休憩/長休憩）の
/// 自動進行・自動保存・BGM/チャイム再生を独自に扱う。
/// 表示は常に `activeTimerStreamProvider` の最新値を反映する。
class PomodoroLockScreen extends ConsumerStatefulWidget {
  const PomodoroLockScreen({
    super.key,
    required this.initialTimer,
    required this.initialTask,
    this.showStartFlash = false,
  });

  /// 起動時点の ActiveTimer（`pomodoro` が非null であること）。
  final ActiveTimer initialTimer;

  /// 対象タスク。削除済み復元時は null。
  final CalendarTask? initialTask;

  /// スタート起点で開いたときのみ true（「スタート！」演出用）。
  final bool showStartFlash;

  @override
  ConsumerState<PomodoroLockScreen> createState() =>
      _PomodoroLockScreenState();
}

class _PomodoroLockScreenState extends ConsumerState<PomodoroLockScreen>
    with WidgetsBindingObserver {
  final GlobalKey _closeButtonKey = GlobalKey();
  Timer? _ticker;

  // 自画面の操作（✕・完了）でドキュメントを消す最中は、stream の null を
  // 「他端末からの削除」と誤認して自動 pop しないようにするためのフラグ。
  bool _closing = false;
  bool _isCompleting = false;

  // フェーズ遷移コミットの多重実行防止。
  bool _transitionCommitting = false;

  // saveProgress失敗の通知は初回のみ（以後の遷移では黙って継続）。
  bool _saveFailureNotified = false;

  // クエスト名・「見込み」・「現状」編集用のコントローラ／フォーカス。
  late final TextEditingController _titleController;
  final FocusNode _titleFocus = FocusNode();
  late final TextEditingController _predictedController;
  final FocusNode _predictedFocus = FocusNode();
  late final TextEditingController _minutesController;
  final FocusNode _minutesFocus = FocusNode();
  bool _titleCommitting = false;
  bool _predictedCommitting = false;
  bool _minutesCommitting = false;

  late ActiveTimer _lastTimer;
  CalendarTask? _task;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastTimer = widget.initialTimer;
    _task = widget.initialTask;
    _titleController = TextEditingController(text: _displayTaskTitle);
    _titleFocus.addListener(() {
      if (!_titleFocus.hasFocus) _commitTitle();
    });
    _predictedController =
        TextEditingController(text: _lastTimer.predictedMinutes.toString());
    _predictedFocus.addListener(() {
      if (!_predictedFocus.hasFocus) _commitPredicted();
    });
    _minutesController =
        TextEditingController(text: _displayTotalMinutes.toString());
    _minutesFocus.addListener(() {
      if (!_minutesFocus.hasFocus) _commitMinutes();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      _maybeCommitTransition();
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
    _titleController.dispose();
    _titleFocus.dispose();
    _predictedController.dispose();
    _predictedFocus.dispose();
    _minutesController.dispose();
    _minutesFocus.dispose();
    super.dispose();
  }

  String get _displayTaskTitle => _task?.title ?? _lastTimer.taskTitle;

  int get _displayTotalMinutes {
    final run = _lastTimer.pomodoro;
    if (run == null) return 0;
    return run.baseActualMinutes + run.savedWorkPhases * run.workMinutes;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // バックグラウンド復帰後、次のtickを待たずに経過を即時反映する。
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      _maybeCommitTransition();
    }
  }

  PomodoroSchedule _scheduleFor(ActiveTimer timer) =>
      PomodoroSchedule(timer.pomodoro!);

  String _phaseLabel(PomodoroPhaseType type) {
    switch (type) {
      case PomodoroPhaseType.work:
        return 'クエスト中';
      case PomodoroPhaseType.shortBreak:
        return '休憩中';
      case PomodoroPhaseType.longBreak:
        return '長休憩中';
    }
  }

  PomodoroBgm _bgmFor(ActiveTimer timer, PomodoroPhaseType type) {
    final run = timer.pomodoro!;
    switch (type) {
      case PomodoroPhaseType.work:
        return PomodoroBgm.fromId(run.bgmWork, PomodoroSettings.defaultBgmWork);
      case PomodoroPhaseType.shortBreak:
        return PomodoroBgm.fromId(
            run.bgmShortBreak, PomodoroSettings.defaultBgmShortBreak);
      case PomodoroPhaseType.longBreak:
        return PomodoroBgm.fromId(
            run.bgmLongBreak, PomodoroSettings.defaultBgmLongBreak);
    }
  }

  PomodoroChime _chimeFor(ActiveTimer timer, PomodoroPhaseType type) {
    final run = timer.pomodoro!;
    switch (type) {
      case PomodoroPhaseType.work:
        return PomodoroChime.fromId(
            run.soundWorkStart, PomodoroSettings.defaultSoundWorkStart);
      case PomodoroPhaseType.shortBreak:
        return PomodoroChime.fromId(run.soundShortBreakStart,
            PomodoroSettings.defaultSoundShortBreakStart);
      case PomodoroPhaseType.longBreak:
        return PomodoroChime.fromId(run.soundLongBreakStart,
            PomodoroSettings.defaultSoundLongBreakStart);
    }
  }

  String _elapsedLabel(int remainingSec) {
    final d = Duration(seconds: remainingSec);
    final m = d.inMinutes.remainder(100).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// クエスト名の確定処理：フォーカスを失ったとき／キーボード完了時に呼ぶ。
  /// タスク種別を問わず自アプリ Firestore の tasks doc + active_timer の
  /// taskTitle を更新する（削除済み復元時は tasks doc 更新をスキップ）。
  Future<void> _commitTitle() async {
    if (_titleCommitting) return;
    final newTitle = _titleController.text.trim();
    final currentTitle = _displayTaskTitle;
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
      });
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          const SnackBar(content: Text('クエスト名を保存できませんでした')),
        );
      }
      _titleController.text = currentTitle;
    } finally {
      _titleCommitting = false;
    }
  }

  /// 「見込み」の確定処理：フォーカスを失ったとき／キーボード完了時に呼ぶ。
  /// active_timer 側の predictedMinutes を更新する
  /// （saveProgress/complete が参照する値のため即時反映が必要）。
  Future<void> _commitPredicted() async {
    if (_predictedCommitting) return;
    final parsed = int.tryParse(_predictedController.text.trim());
    final current = _lastTimer.predictedMinutes;
    if (parsed == null || parsed == current) {
      _predictedController.text = current.toString();
      return;
    }
    _predictedCommitting = true;
    try {
      await ref.read(activeTimerRepositoryProvider).updatePredictedMinutes(parsed);
      if (!mounted) return;
      setState(() {
        _lastTimer = _lastTimer.copyWith(predictedMinutes: parsed);
      });
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          const SnackBar(content: Text('見込み時間を保存できませんでした')),
        );
      }
      _predictedController.text = current.toString();
    } finally {
      _predictedCommitting = false;
    }
  }

  /// 「現状」の確定処理：フォーカスを失ったとき／キーボード完了時に呼ぶ。
  /// active_timer 側をトランザクションで確定させた後、tasks doc へも即時
  /// 反映する（✕クローズの addedMinutes==0 early-return で編集が消えないように）。
  Future<void> _commitMinutes() async {
    if (_minutesCommitting) return;
    final parsed = int.tryParse(_minutesController.text.trim());
    final currentTotal = _displayTotalMinutes;
    if (parsed == null || parsed == currentTotal) {
      _minutesController.text = currentTotal.toString();
      return;
    }
    _minutesCommitting = true;
    try {
      final result = await ref
          .read(activeTimerRepositoryProvider)
          .commitPomodoroBaseActualMinutes(newTotalMinutes: parsed);
      if (result == null) {
        _minutesController.text = currentTotal.toString();
        return;
      }
      if (!mounted) return;
      _minutesController.text = result.totalMinutes.toString();
      setState(() {
        final run = _lastTimer.pomodoro;
        if (run != null) {
          _lastTimer = _lastTimer.copyWith(
            pomodoro: run.copyWith(baseActualMinutes: result.baseActualMinutes),
          );
        }
      });

      final saveOk = await ref.read(timerActionsProvider).saveProgress(
            taskId: _lastTimer.taskId,
            predictedMinutes: _lastTimer.predictedMinutes,
            actualMinutes: result.totalMinutes,
          );
      if (!mounted) return;
      if (!saveOk) {
        showAppSnackBar(
          context,
          const SnackBar(content: Text('現状の時間を保存できませんでした')),
        );
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          const SnackBar(content: Text('現状の時間を保存できませんでした')),
        );
      }
      _minutesController.text = currentTotal.toString();
    } finally {
      _minutesCommitting = false;
    }
  }

  /// クエスト名・「見込み」・「現状」の未確定編集をフラッシュする。
  /// complete/close/pause の各操作の直前に必ず await すること
  /// （ボタンタップはフォーカスを奪わないため、確定処理が走らないまま
  /// actualMinutes 計算に進んでしまう Critical な不整合を防ぐ）。
  Future<void> _flushPendingEdits() async {
    FocusScope.of(context).unfocus();
    if (_titleController.text.trim() != _displayTaskTitle) {
      await _commitTitle();
    }
    final currentPredicted = _lastTimer.predictedMinutes;
    final parsedPredicted = int.tryParse(_predictedController.text.trim());
    if (parsedPredicted != null && parsedPredicted != currentPredicted) {
      await _commitPredicted();
    }
    final currentTotal = _displayTotalMinutes;
    final parsedMinutes = int.tryParse(_minutesController.text.trim());
    if (parsedMinutes != null && parsedMinutes != currentTotal) {
      await _commitMinutes();
    }
  }

  /// フェーズ遷移のコミット：描画時に実効 phaseIndex > doc の phaseIndex を
  /// 検知したら、doc を実効値へ update（新フェーズの phaseStartedAtUtc には
  /// 理論境界時刻を書きドリフトを防ぐ）→ 新規完了クエスト分を自動保存
  /// → チャイム+BGM切り替え、を行う。
  Future<void> _maybeCommitTransition() async {
    if (!mounted || _transitionCommitting || _closing) return;
    final timer = _lastTimer;
    final run = timer.pomodoro;
    if (run == null || !run.isRunning) return;

    final schedule = _scheduleFor(timer);
    final now = DateTime.now();
    final effective = schedule.currentPhase(now);
    if (effective.phaseIndex <= run.phaseIndex) return;

    _transitionCommitting = true;
    try {
      final completedDelta =
          schedule.completedWorkPhasesUntil(effective.phaseIndex);
      final newSavedWorkPhases = run.savedWorkPhases + completedDelta;

      // 理論境界時刻（前フェーズ開始 + 経過したフェーズ長の合計）を計算する。
      // 一時停止で貯まった phaseAccumulatedSeconds の分だけ実際の境界は
      // 早く来るため、先に差し引く（差し引かないと未来時刻が書き込まれ、
      // 新フェーズのタイマー表示がその分だけ凍結する）。
      var boundary = run.phaseStartedAtUtc!
          .subtract(Duration(seconds: run.phaseAccumulatedSeconds));
      for (var i = run.phaseIndex; i < effective.phaseIndex; i++) {
        boundary =
            boundary.add(Duration(seconds: schedule.phaseLengthSecondsAt(i)));
      }

      final ok = await ref.read(activeTimerRepositoryProvider).commitPomodoroTransition(
            expectedCurrentPhaseIndex: run.phaseIndex,
            newPhaseIndex: effective.phaseIndex,
            phaseStartedAtUtc: boundary,
            newSavedWorkPhases: newSavedWorkPhases,
          );
      if (!ok || !mounted) return; // 他端末が既にコミット済み（冪等）／画面が破棄済み。

      if (completedDelta > 0) {
        final total = run.baseActualMinutes + newSavedWorkPhases * run.workMinutes;
        final saveOk = await ref.read(timerActionsProvider).saveProgress(
              taskId: timer.taskId,
              predictedMinutes: timer.predictedMinutes,
              actualMinutes: total,
            );
        if (!mounted) return;
        if (!saveOk && !_saveFailureNotified) {
          _saveFailureNotified = true;
          showAppSnackBar(
            context,
            const SnackBar(content: Text('作業時間を保存できませんでした')),
          );
        }
      }

      final audio = ref.read(pomodoroAudioProvider);
      try {
        await audio.playPhase(
          bgm: _bgmFor(timer, effective.type),
          chime: _chimeFor(timer, effective.type),
        );
      } catch (_) {
        // 音の失敗でフェーズ進行を止めない。
      }
    } finally {
      _transitionCommitting = false;
    }
  }

  Future<void> _togglePauseResume(ActiveTimer timer) async {
    await _flushPendingEdits();
    if (!mounted) return;
    final current = _lastTimer;
    final repo = ref.read(activeTimerRepositoryProvider);
    final run = current.pomodoro!;
    final audio = ref.read(pomodoroAudioProvider);
    if (run.isRunning) {
      final elapsed =
          _scheduleFor(current).currentPhase(DateTime.now()).elapsedSeconds;
      await repo.pausePomodoro(current, elapsed);
      await audio.pause();
    } else {
      await repo.resumePomodoro();
      await audio.resume();
    }
  }

  /// 休憩スキップ（休憩・長休憩中かつ実行中のみ）：次のクエストへ進め、
  /// フェーズ時計をリセットし、クエスト開始音＋クエストBGMを鳴らす。
  Future<void> _onTapSkipBreak(ActiveTimer timer) async {
    final run = timer.pomodoro!;
    final schedule = _scheduleFor(timer);
    final currentEffective = schedule.currentPhase(DateTime.now());
    final nextIndex = currentEffective.phaseIndex + 1;
    final ok = await ref.read(activeTimerRepositoryProvider).commitPomodoroTransition(
          expectedCurrentPhaseIndex: currentEffective.phaseIndex,
          newPhaseIndex: nextIndex,
          phaseStartedAtUtc: DateTime.now(),
          newSavedWorkPhases: run.savedWorkPhases,
        );
    if (!ok) return;
    final audio = ref.read(pomodoroAudioProvider);
    try {
      await audio.playPhase(
        bgm: _bgmFor(timer, PomodoroPhaseType.work),
        chime: _chimeFor(timer, PomodoroPhaseType.work),
      );
    } catch (_) {
      // 音の失敗で休憩スキップを止めない。
    }
  }

  /// クエストスキップ（クエスト中かつ実行中のみ）：休憩へ進め、
  /// フェーズ時計をリセットし、休憩開始音＋休憩BGMを鳴らす。
  /// 現フェーズの経過分は完了扱いにしない（savedWorkPhasesは変更しない）。
  Future<void> _onTapSkipQuest(ActiveTimer timer) async {
    final run = timer.pomodoro!;
    final schedule = _scheduleFor(timer);
    final currentEffective = schedule.currentPhase(DateTime.now());
    final nextIndex = currentEffective.phaseIndex + 1;
    final nextType = schedule.phaseTypeAt(nextIndex);
    final ok = await ref.read(activeTimerRepositoryProvider).commitPomodoroTransition(
          expectedCurrentPhaseIndex: currentEffective.phaseIndex,
          newPhaseIndex: nextIndex,
          phaseStartedAtUtc: DateTime.now(),
          newSavedWorkPhases: run.savedWorkPhases,
        );
    if (!ok) return;
    final audio = ref.read(pomodoroAudioProvider);
    try {
      await audio.playPhase(
        bgm: _bgmFor(timer, nextType),
        chime: _chimeFor(timer, nextType),
      );
    } catch (_) {
      // 音の失敗でクエストスキップを止めない。
    }
  }

  /// 完了：running なら実効状態で確定。
  /// actualMinutes = base + 完了クエスト数×N + (現フェーズがクエストなら経過分切り捨て)。
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
    final run = current.pomodoro!;
    final schedule = _scheduleFor(current);
    final now = DateTime.now();
    final effective = schedule.currentPhase(now);
    final totalCompletedWorkPhases =
        run.savedWorkPhases + schedule.completedWorkPhasesUntil(effective.phaseIndex);
    final inProgressWorkMinutes =
        effective.type == PomodoroPhaseType.work ? effective.elapsedSeconds ~/ 60 : 0;
    final total = run.baseActualMinutes +
        totalCompletedWorkPhases * run.workMinutes +
        inProgressWorkMinutes;
    final actualMinutes = total > 0 ? total : null;

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
          predictedMinutes: current.predictedMinutes,
          actualMinutes: actualMinutes,
        );
    if (!mounted) return;
    if (outcome == null) {
      setState(() => _isCompleting = false);
      showAppSnackBar(context, const SnackBar(content: Text('完了処理に失敗しました')));
      return;
    }

    await ref.read(pomodoroAudioProvider).stop();
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

  /// ✕（一時停止中のみ閉じられる）：完了と同じ式で actualMinutes を計算し
  /// saveProgress → doc clear → pop。計測ゼロなら保存せず破棄。
  Future<void> _onTapClose(ActiveTimer timer) async {
    // 動作中は閉じられないガードは flush 前に行う（flush は閉じ操作ではない）。
    final runBeforeFlush = timer.pomodoro!;
    if (runBeforeFlush.isRunning) {
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
    final run = current.pomodoro!;
    final schedule = _scheduleFor(current);
    final effective = schedule.currentPhase(DateTime.now());
    final totalCompletedWorkPhases =
        run.savedWorkPhases + schedule.completedWorkPhasesUntil(effective.phaseIndex);
    final inProgressWorkMinutes =
        effective.type == PomodoroPhaseType.work ? effective.elapsedSeconds ~/ 60 : 0;
    final addedMinutes = totalCompletedWorkPhases * run.workMinutes + inProgressWorkMinutes;

    await ref.read(pomodoroAudioProvider).stop();

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

    final total = run.baseActualMinutes + addedMinutes;
    final ok = await ref.read(timerActionsProvider).saveProgress(
          taskId: current.taskId,
          predictedMinutes: current.predictedMinutes,
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

    // クエスト名・「現状」のコントローラは、非フォーカス時 かつ 値が変化した
    // ときのみ外部の最新値へ同期する（毎秒 setState・stream 更新で入力中の
    // テキストを潰さないため、build内では直接書き換えない）。
    ref.listen<AsyncValue<ActiveTimer?>>(activeTimerStreamProvider, (prev, next) {
      final timer = next.asData?.value;
      if (timer == null || timer.pomodoro == null) return;
      _lastTimer = timer;
      if (!_titleFocus.hasFocus && _titleController.text != _displayTaskTitle) {
        _titleController.text = _displayTaskTitle;
      }
      final predicted = timer.predictedMinutes;
      if (!_predictedFocus.hasFocus &&
          _predictedController.text != predicted.toString()) {
        _predictedController.text = predicted.toString();
      }
      final total = _displayTotalMinutes;
      if (!_minutesFocus.hasFocus && _minutesController.text != total.toString()) {
        _minutesController.text = total.toString();
      }
    });

    final asyncTimer = ref.watch(activeTimerStreamProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final timer = asyncTimer.asData?.value ?? _lastTimer;
        await _onTapClose(timer);
      },
      child: Scaffold(
        body: MessageGuard(
          child: asyncTimer.when(
            data: (timer) {
              if (timer == null || timer.pomodoro == null) {
                if (!_closing) {
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
    final run = timer.pomodoro!;
    final running = run.isRunning;
    final schedule = _scheduleFor(timer);
    final state = schedule.currentPhase(DateTime.now());
    final canSkipBreak =
        running && state.type != PomodoroPhaseType.work;
    final canSkipQuest =
        running && state.type == PomodoroPhaseType.work;

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
                        style:
                            text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        decoration: const InputDecoration(
                          filled: true,
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'セット ${state.setNumber} / ${run.setCount}',
                        style:
                            text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const Spacer(),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _phaseLabel(state.type),
                          style: text.displayLarge?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Center(
                        child: Text(
                          _elapsedLabel(state.remainingSeconds),
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
                                child: TextField(
                                  controller: _predictedController,
                                  focusNode: _predictedFocus,
                                  keyboardType: const TextInputType.numberWithOptions(
                                      decimal: false),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(4),
                                  ],
                                  textAlign: TextAlign.center,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _commitPredicted(),
                                  style: text.titleLarge?.copyWith(
                                    fontFeatures: const [FontFeature.tabularFigures()],
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
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('現状', style: text.labelLarge),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 140,
                                child: TextField(
                                  controller: _minutesController,
                                  focusNode: _minutesFocus,
                                  keyboardType: const TextInputType.numberWithOptions(
                                      decimal: false),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(4),
                                  ],
                                  textAlign: TextAlign.center,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _commitMinutes(),
                                  style: text.titleLarge?.copyWith(
                                    fontFeatures: const [FontFeature.tabularFigures()],
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
                      if (canSkipBreak) ...[
                        OutlinedButton.icon(
                          onPressed: () => _onTapSkipBreak(timer),
                          icon: const Icon(Icons.skip_next_rounded),
                          label: const Text('休憩をスキップ'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ] else if (canSkipQuest) ...[
                        OutlinedButton.icon(
                          onPressed: () => _onTapSkipQuest(timer),
                          icon: const Icon(Icons.skip_next_rounded),
                          label: const Text('クエストをスキップして休憩へ'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FilledButton.icon(
                        onPressed: () => _togglePauseResume(timer),
                        icon: Icon(
                            running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        label: Text(running ? '一時停止' : '再開'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _isCompleting ? null : () => _onTapComplete(timer),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('完了'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
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
