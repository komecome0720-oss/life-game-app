import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/features/health/model/health_rollover.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_day.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_schedule.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_settings.dart';
import 'package:task_manager/features/pomodoro/providers/pomodoro_day_providers.dart';
import 'package:task_manager/features/pomodoro/providers/pomodoro_providers.dart';
import 'package:task_manager/features/pomodoro/view/pomodoro_lock_screen.dart';
import 'package:task_manager/features/timer/model/active_timer.dart';
import 'package:task_manager/features/timer/model/pomodoro_run.dart';
import 'package:task_manager/features/timer/providers/timer_providers.dart';
import 'package:task_manager/features/timer/view/timer_lock_screen.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/utils/app_messenger.dart';

/// ロック画面 push の唯一の起動口。
///
/// 「シート起点」と「起動時の復元 listen」の二重pushを構造的に防ぐため、
/// 表示中フラグを同期的に立ててから Firestore 書き込み・push を行う。
/// シート側はここを直接呼ばず、`TaskSheetResult.startTimer` /
/// `TaskSheetResult.startPomodoro` を返して閉じるだけにする
/// （呼び出し元が安定した context でこのクラスを呼ぶ）。
///
/// スタートはローカルファースト：既存docの有無は常時 listen 中の
/// `activeTimerStreamProvider` のメモリ値で判定し、新規docの書き込みは
/// await せずに即ロック画面を開く（オフライン永続化によりローカルへは
/// 即時反映され、サーバへはバックグラウンドで同期される）。これにより
/// スタート操作から画面表示までにネットワーク往復を挟まない。
/// ストリーム未確定時（起動直後など）のみ従来のサーバ確認つき経路に落とす。
///
/// 既存docがある場合、その `pomodoro` 有無と起動経路が食い違うことがある
/// （例: ポモドーロdoc残存中に通常スタート）。この場合は doc の型を正として
/// 画面を振り分け、食い違いをユーザーへ通知する。
///
/// [predictedMinutes] は宣言済みの値を渡すこと（予測宣言チップシートで選ばれた値、
/// または再開時は既存の宣言値）。既存タイマーが存続している間は渡した値を無視して
/// 既存docを再開するため、呼び出し側は既存タイマーの有無を先に確認し、存続時は
/// チップシートの表示をスキップすること（宣言＝スタート動作のため、既存タイマー
/// 再開時に新たな宣言を求めても意味を持たない）。
/// クイックスタート（FAB長押し）で作成するタスクの既定タイトル。
const String kQuickStartDefaultTitle = 'クイックスタート';

class TimerLockLauncher {
  TimerLockLauncher._();

  static bool _visible = false;

  /// `openForQuickStart` のタスク作成〜起動処理中の二重再入防止フラグ
  /// （`_visible` とは別。`_visible` を流用すると入れ子の open* 呼び出しが
  /// 早期returnしてしまうため分離する）。
  static bool _quickStarting = false;

  /// 現在ロック画面を表示中（起動処理中を含む）かどうか。
  static bool get isVisible => _visible;

  /// シートの「スタート」ボタンから呼ばれる起動口（通常タイマー）。
  /// 既にタイマーが存在する場合は上書きせずそれを使う（repository.start の仕様）。
  /// [quickStart] は新規スタート時のみ `ActiveTimer` に反映する
  /// （既存doc再開・型ミスマッチ分岐では常に false のまま扱う）。
  static Future<void> openForStart(
    BuildContext context,
    WidgetRef ref, {
    required CalendarTask task,
    required int predictedMinutes,
    bool quickStart = false,
  }) async {
    if (_visible) return; // 二重起動防止
    _visible = true; // Firestore書き込みより必ず前に同期的にON
    try {
      final asyncTimer = ref.read(activeTimerStreamProvider);
      final ActiveTimer timer;
      if (!asyncTimer.hasValue) {
        // ストリーム未確定（起動直後など）のみ従来のサーバ確認つき経路。
        timer = await ref.read(activeTimerRepositoryProvider).start(
              taskId: task.id,
              isTodo: task.isTodo,
              taskTitle: task.title,
              predictedMinutes: predictedMinutes,
              quickStart: quickStart,
            );
      } else if (asyncTimer.value != null) {
        // 既存タイマーはメモリ値をそのまま尊重（Firestoreアクセスなし）。
        timer = asyncTimer.value!;
      } else {
        // 新規スタート：書き込み完了を待たずに即開く（ローカルファースト）。
        final started = ref.read(activeTimerRepositoryProvider).startLocalFirst(
              taskId: task.id,
              isTodo: task.isTodo,
              taskTitle: task.title,
              predictedMinutes: predictedMinutes,
              quickStart: quickStart,
            );
        timer = started.timer;
        _notifyOnWriteFailure(context, started.write);
      }
      if (!context.mounted) return;
      if (timer.pomodoro != null) {
        // 既存docがポモドーロだった場合はそちらを開く（doc の型が正）。
        showAppSnackBar(
          context,
          const SnackBar(content: Text('計測中のタイマーがあるため再開します')),
        );
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => PomodoroLockScreen(
              initialTimer: timer,
              initialTask: task,
              quickStart: false,
            ),
          ),
        );
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => TimerLockScreen(
            initialTimer: timer,
            initialTask: task,
            showStartFlash: true,
            quickStart: quickStart,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          SnackBar(content: Text('タイマーの開始に失敗しました: $e')),
        );
      }
    } finally {
      _visible = false;
    }
  }

  /// シートの「ポモドーロ」ボタンから呼ばれる起動口。
  /// 既にタイマーが存在する場合は上書きせずそれを使う（startPomodoro の仕様）。
  /// [quickStart] は新規スタート時のみ `ActiveTimer` に反映する
  /// （既存doc再開・型ミスマッチ分岐では常に false のまま扱う）。
  static Future<void> openForPomodoro(
    BuildContext context,
    WidgetRef ref, {
    required CalendarTask task,
    required int predictedMinutes,
    bool quickStart = false,
  }) async {
    if (_visible) return;
    _visible = true;
    try {
      final baseActualMinutes = task.actualMinutes ?? 0;
      final asyncTimer = ref.read(activeTimerStreamProvider);
      final ActiveTimer timer;
      if (!asyncTimer.hasValue) {
        // ストリーム未確定（起動直後など）のみ従来のサーバ確認つき経路。
        final settings =
            await ref.read(pomodoroSettingsRepositoryProvider).read();
        final resolved = await _resolvePomodoroDayStart(ref, settings);
        timer = await ref.read(activeTimerRepositoryProvider).startPomodoro(
              taskId: task.id,
              isTodo: task.isTodo,
              taskTitle: task.title,
              predictedMinutes: predictedMinutes,
              settings: settings,
              baseActualMinutes: baseActualMinutes,
              dateKey: resolved.dateKey,
              dayStart: resolved.dayStart,
              quickStart: quickStart,
            );
      } else if (asyncTimer.value != null) {
        // 既存タイマーはメモリ値をそのまま尊重（Firestoreアクセスなし）。
        timer = asyncTimer.value!;
      } else {
        // 新規スタート：設定は常時listenのメモリ値を優先し、書き込み完了を
        // 待たずに即開く（ローカルファースト）。「1日通しセット」の開始位置
        // 解決のみ、pomodoroDayStreamProvider のメモリ値が未確定な場合に限り
        // Firestore を直接読む（`_resolvePomodoroDayStart` 内）。
        final settings = ref.read(pomodoroSettingsStreamProvider).value ??
            await ref.read(pomodoroSettingsRepositoryProvider).read();
        if (!context.mounted) return;
        final resolved = await _resolvePomodoroDayStart(ref, settings);
        if (!context.mounted) return;
        final started =
            ref.read(activeTimerRepositoryProvider).startPomodoroLocalFirst(
                  taskId: task.id,
                  isTodo: task.isTodo,
                  taskTitle: task.title,
                  predictedMinutes: predictedMinutes,
                  settings: settings,
                  baseActualMinutes: baseActualMinutes,
                  dateKey: resolved.dateKey,
                  dayStart: resolved.dayStart,
                  quickStart: quickStart,
                );
        timer = started.timer;
        _notifyOnWriteFailure(context, started.write);
      }
      if (!context.mounted) return;
      if (timer.pomodoro == null) {
        // 既存docが通常タイマーだった場合はそちらを開く（doc の型が正）。
        showAppSnackBar(
          context,
          const SnackBar(content: Text('計測中のタイマーがあるため再開します')),
        );
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => TimerLockScreen(
              initialTimer: timer,
              initialTask: task,
              quickStart: false,
            ),
          ),
        );
        return;
      }
      // 新規スタート時のクエスト開始音。音声セッション初期化やBGMロードで
      // ロック画面の表示を待たせないよう await しない。音の失敗でロック画面が
      // 開けなくなるのも避けたいので、エラーは握りつぶす。
      final run = timer.pomodoro!;
      final schedule = PomodoroSchedule(run);
      final firstPhase = schedule.phaseTypeAt(run.phaseIndex);
      unawaited(ref
          .read(pomodoroAudioProvider)
          .playPhase(
            bgm: _bgmForPhase(run, firstPhase),
            chime: _chimeForPhase(run, firstPhase),
          )
          .catchError((Object _) {
        // 音が鳴らなくてもタイマー自体は開始できる。
      }));
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => PomodoroLockScreen(
            initialTimer: timer,
            initialTask: task,
            showStartFlash: true,
            quickStart: quickStart,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          SnackBar(content: Text('ポモドーロの開始に失敗しました: $e')),
        );
      }
    } finally {
      _visible = false;
    }
  }

  /// アプリ起動時の復元 listen から呼ばれる起動口。
  /// [task] は呼び出し側が fetchTaskById 等で解決済みのものを渡す。
  /// `timerSnapshot.pomodoro` が非null ならポモドーロのロック画面を開く。
  static Future<void> openForRestore(
    BuildContext context,
    WidgetRef ref, {
    required ActiveTimer timerSnapshot,
    required CalendarTask? task,
  }) async {
    if (_visible) return;
    _visible = true;
    try {
      if (!context.mounted) return;
      if (timerSnapshot.pomodoro != null) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => PomodoroLockScreen(
              initialTimer: timerSnapshot,
              initialTask: task,
              quickStart: timerSnapshot.quickStart,
            ),
          ),
        );
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => TimerLockScreen(
            initialTimer: timerSnapshot,
            initialTask: task,
            quickStart: timerSnapshot.quickStart,
          ),
        ),
      );
    } finally {
      _visible = false;
    }
  }

  /// FAB長押し（クイックスタート）からの起動口。カレンダー予定を1件
  /// （タイトル＝[kQuickStartDefaultTitle]・開始/終了=now・見込み0・
  /// `predictionDeclared: true`）作成し、即ロック画面を開く。
  ///
  /// 作成前に `activeTimer` の有無を確認し、既に計測中なら新規タスクは作らず
  /// その計測中のロック画面を開き直す（保険。通常は起きない前提）。
  ///
  /// `_visible` とは別に `_quickStarting` で二重再入を防ぐ
  /// （タスク作成のFirestore往復中に再度呼ばれてゴミタスクが二重生成されるのを防止）。
  static Future<void> openForQuickStart(
    BuildContext context,
    WidgetRef ref, {
    required bool pomodoro,
  }) async {
    if (_visible || _quickStarting) return;
    _quickStarting = true;
    try {
      final asyncTimer = ref.read(activeTimerStreamProvider);
      if (asyncTimer.hasValue && asyncTimer.value != null) {
        final existing = asyncTimer.value!;
        showAppSnackBar(
          context,
          const SnackBar(content: Text('計測中のタイマーがあります')),
        );
        final resolved =
            await resolveTaskForStart(ref, taskId: existing.taskId);
        if (!context.mounted) return;
        await openForRestore(
          context,
          ref,
          timerSnapshot: existing,
          task: resolved,
        );
        return;
      }
      final now = DateTime.now();
      final taskId =
          await ref.read(calendarTaskSyncRepositoryProvider).createTaskFull(
                title: kQuickStartDefaultTitle,
                start: now,
                end: now,
                predictionDeclared: true,
              );
      final quickTask = CalendarTask(
        id: taskId,
        title: kQuickStartDefaultTitle,
        start: now,
        end: now,
        rewardYen: 0,
        isTodo: false,
        predictedMinutes: 0,
        predictionDeclared: true,
      );
      if (!context.mounted) return;
      if (pomodoro) {
        await openForPomodoro(
          context,
          ref,
          task: quickTask,
          predictedMinutes: 0,
          quickStart: true,
        );
      } else {
        await openForStart(
          context,
          ref,
          task: quickTask,
          predictedMinutes: 0,
          quickStart: true,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          SnackBar(content: Text('クイックスタートの開始に失敗しました: $e')),
        );
      }
    } finally {
      _quickStarting = false;
    }
  }

  /// 「1日通しセット」の開始位置を解決する。dateKey は現在（端末ローカル）の
  /// 日付。day doc は常時listen中の `pomodoroDayStreamProvider` のメモリ値を
  /// 優先し、未確定（起動直後・直前に closePomodoroRun したばかりで stream が
  /// 追いついていない可能性がある場合）のみ Firestore を直接読む。
  static Future<({String dateKey, PomodoroDayStart dayStart})>
      _resolvePomodoroDayStart(WidgetRef ref, PomodoroSettings settings) async {
    final nowUtc = DateTime.now().toUtc();
    final dateKey = HealthRollover.dateKey(DateTime.now());
    final asyncDay = ref.read(pomodoroDayStreamProvider);
    final day = asyncDay.hasValue
        ? asyncDay.value
        : await ref.read(pomodoroDayRepositoryProvider).readToday();
    final dayStart = (day ?? PomodoroDay.empty(nowUtc))
        .resolveStart(settings: settings, nowUtc: nowUtc);
    return (dateKey: dateKey, dayStart: dayStart);
  }

  /// ローカルファースト書き込みの失敗を事後通知する（画面は既に開いている）。
  /// オフラインはFirestoreの永続化が再送するためここには来ない。ルール拒否等の
  /// 恒久的な失敗のみが対象。
  static void _notifyOnWriteFailure(BuildContext context, Future<void> write) {
    unawaited(write.catchError((Object e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          SnackBar(content: Text('タイマーの同期に失敗しました: $e')),
        );
      }
    }));
  }
}

PomodoroBgm _bgmForPhase(PomodoroRun run, PomodoroPhaseType type) {
  switch (type) {
    case PomodoroPhaseType.work:
      return PomodoroBgm.fromId(run.bgmWork, PomodoroBgm.waves);
    case PomodoroPhaseType.shortBreak:
      return PomodoroBgm.fromId(run.bgmShortBreak, PomodoroBgm.river);
    case PomodoroPhaseType.longBreak:
      return PomodoroBgm.fromId(run.bgmLongBreak, PomodoroBgm.birds);
  }
}

PomodoroChime _chimeForPhase(PomodoroRun run, PomodoroPhaseType type) {
  switch (type) {
    case PomodoroPhaseType.work:
      return PomodoroChime.fromId(run.soundWorkStart, PomodoroChime.drum);
    case PomodoroPhaseType.shortBreak:
      return PomodoroChime.fromId(run.soundShortBreakStart, PomodoroChime.bell);
    case PomodoroPhaseType.longBreak:
      return PomodoroChime.fromId(
          run.soundLongBreakStart, PomodoroChime.trumpet);
  }
}

/// promoteRemoteTaskIfNeeded 失敗時など、起動前にタスクIDが未確定の場合の
/// ヘルパー。呼び出し元（home_screen 等）で使う。
Future<CalendarTask?> resolveTaskForStart(
  WidgetRef ref, {
  required String taskId,
}) {
  return ref.read(calendarTaskSyncRepositoryProvider).fetchTaskById(taskId);
}
