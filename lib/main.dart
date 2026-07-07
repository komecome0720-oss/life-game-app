import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/adventure_log/providers/adventure_log_providers.dart';
import 'package:task_manager/features/adventure_log/providers/daily_earnings_providers.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:task_manager/features/auth/presentation/login_screen.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';
import 'package:task_manager/features/onboarding/onboarding_keys.dart';
import 'package:task_manager/features/onboarding/view/onboarding_gate.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_schedule.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_settings.dart';
import 'package:task_manager/features/pomodoro/providers/pomodoro_providers.dart';
import 'package:task_manager/features/timer/model/active_timer.dart';
import 'package:task_manager/features/timer/providers/timer_providers.dart';
import 'package:task_manager/features/timer/view/timer_lock_launcher.dart';
import 'package:task_manager/features/timer/viewmodel/timer_actions.dart';
import 'package:task_manager/features/todo/providers/todo_providers.dart';
import 'package:task_manager/features/todo/view/todo_matrix_screen.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/features/wish_list/view/wish_list_screen.dart';
import 'package:task_manager/firebase_options.dart';
import 'package:task_manager/screens/home_screen.dart';
import 'package:task_manager/theme/app_tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // トマトアイコン（Twemoji）の CC-BY 4.0 帰属表示。
  // Flutter 標準のライセンス画面（showLicensePage 等）に表示される。
  // 詳細は assets/images/LICENSES.md 参照。
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Twemoji'],
      'Tomato icon (assets/images/tomato_twemoji.png) is derived from Twemoji.\n'
      'Copyright 2020 Twitter, Inc and other contributors.\n'
      'Graphics licensed under CC-BY 4.0: '
      'https://creativecommons.org/licenses/by/4.0/\n'
      'Source: https://github.com/jdecked/twemoji (assets/svg/1f345.svg)\n'
      'Modifications: rasterized to PNG and background made transparent.',
    );
  });
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('ja_JP');
  runApp(const ProviderScope(child: TaskManagerApp()));
}

class TaskManagerApp extends ConsumerWidget {
  const TaskManagerApp({super.key});

  static const _seedColor = Color(0xFF2E7D6B);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeModeStr = ref.watch(
      userSettingsProvider.select((s) => s.settings.themeMode),
    );
    return MaterialApp(
      title: '人生ゲーム化',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
        useMaterial3: true,
        cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: AppRadius.card)),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: AppRadius.card)),
      ),
      themeMode: _parseThemeMode(themeModeStr),
      home: const _AuthGate(),
    );
  }
}

ThemeMode _parseThemeMode(String s) {
  switch (s) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    return authState.when(
      data: (user) => user != null
          ? const OnboardingGate(child: _MainShell())
          : const LoginScreen(),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const LoginScreen(),
    );
  }
}

class _MainShell extends ConsumerWidget {
  const _MainShell();

  static const _pages = [HomeScreen(), TodoMatrixScreen(), WishListScreen()];

  /// アプリ起動時（およびログイン直後）にアクティブタイマーが残っていたら
  /// ロック画面を復元する。保存直後の空タイマー（停止・0秒）と
  /// 対象タスクが削除済みの場合は、タイマーを破棄して開かない。
  ///
  /// ポモドーロ（`timer.pomodoro != null`）は `startedAtUtc`/`accumulatedSeconds`
  /// を使わないため「停止・0秒の空タイマーは破棄」判定は適用しない。
  /// 代わりに、プロセスごと停止していた場合に備え、実時間から計算した実効
  /// フェーズが doc の phaseIndex を1つ以上越えていたら「+1フェーズ・先頭・
  /// 一時停止」に doc を更新してから画面を開く（確定仕様11・越えた1回分が
  /// クエストなら自動保存する）。
  Future<void> _maybeRestoreTimerLockScreen(
    BuildContext context,
    WidgetRef ref,
    ActiveTimer timer,
  ) async {
    if (TimerLockLauncher.isVisible) return;
    final repo = ref.read(activeTimerRepositoryProvider);

    if (timer.pomodoro != null) {
      final task = await resolveTaskForStart(ref, taskId: timer.taskId);
      if (task == null) {
        await repo.clear();
        return;
      }
      final restoredTimer = await _capPomodoroToOnePhase(ref, timer);
      if (TimerLockLauncher.isVisible || !context.mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || TimerLockLauncher.isVisible) return;
        TimerLockLauncher.openForRestore(
          context,
          ref,
          timerSnapshot: restoredTimer,
          task: task,
        );
      });
      return;
    }

    if (!timer.isRunning && timer.accumulatedSeconds == 0) {
      await repo.clear();
      return;
    }
    final task = await resolveTaskForStart(ref, taskId: timer.taskId);
    if (task == null) {
      await repo.clear();
      return;
    }
    if (TimerLockLauncher.isVisible || !context.mounted) return;
    // ビルド中の push を避けるためフレーム確定後に開く。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted || TimerLockLauncher.isVisible) return;
      TimerLockLauncher.openForRestore(
        context,
        ref,
        timerSnapshot: timer,
        task: task,
      );
    });
  }

  /// ポモドーロ復元専用：実効フェーズが1つ以上越えていたら「+1フェーズ・
  /// 先頭・一時停止」まで進めて doc をコミットし、越えた1回分がクエスト
  /// なら自動保存する。境界内（同一フェーズ）なら doc をそのまま返す。
  Future<ActiveTimer> _capPomodoroToOnePhase(
    WidgetRef ref,
    ActiveTimer timer,
  ) async {
    final run = timer.pomodoro!;
    final schedule = PomodoroSchedule(run);
    final result = schedule.restoreCappedToOnePhase(DateTime.now());
    if (result.run.phaseIndex == run.phaseIndex) {
      return timer; // 同一フェーズ内：変更なし。
    }

    final repo = ref.read(activeTimerRepositoryProvider);
    final committed = await repo.commitPomodoroTransition(
      expectedCurrentPhaseIndex: run.phaseIndex,
      newPhaseIndex: result.run.phaseIndex,
      phaseStartedAtUtc: null, // 一時停止で復元する。
      newSavedWorkPhases: result.run.savedWorkPhases,
    );
    if (!committed) return timer; // 他端末が既に処理済み（冪等）。

    if (result.completedWorkPhases > 0) {
      final total = run.baseActualMinutes + result.run.savedWorkPhases * run.workMinutes;
      await ref.read(timerActionsProvider).saveProgress(
            taskId: timer.taskId,
            predictedMinutes: timer.predictedMinutes,
            actualMinutes: total,
          );
    }
    return timer.copyWith(pomodoro: result.run);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(adventureLogBackfillProvider);
    ref.watch(dailyEarningsBackfillProvider);
    ref.listen<AsyncValue<ActiveTimer?>>(activeTimerStreamProvider, (_, next) {
      final timer = next.asData?.value;
      if (timer == null) return;
      _maybeRestoreTimerLockScreen(context, ref, timer);
    });
    // ポモドーロ設定を常時メモリに保持し、スタート時のFirestore往復を無くす
    // （TimerLockLauncher がこのメモリ値を読む）。
    ref.listen<AsyncValue<PomodoroSettings>>(
      pomodoroSettingsStreamProvider,
      (_, _) {},
    );
    final index = ref.watch(mainTabIndexProvider);
    return Scaffold(
      body: IndexedStack(index: index, children: _pages),
      bottomNavigationBar: NavigationBar(
        height: 50,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(mainTabIndexProvider.notifier).set(i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: KeyedSubtree(
              key: OnboardingKeys.todoTab,
              child: const Icon(Icons.check_box_outlined),
            ),
            selectedIcon: const Icon(Icons.check_box),
            label: 'ToDo',
          ),
          NavigationDestination(
            icon: KeyedSubtree(
              key: OnboardingKeys.wishTab,
              child: const Icon(Icons.favorite_border),
            ),
            selectedIcon: const Icon(Icons.favorite),
            label: '欲しいもの',
          ),
        ],
      ),
    );
  }
}
