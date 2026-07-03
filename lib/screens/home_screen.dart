import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/data/mock_home_data.dart';
import 'package:task_manager/features/adventure_log/view/adventure_log_screen.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';
import 'package:task_manager/features/calendar_sync/model/google_account_info.dart';
import 'package:task_manager/features/calendar_sync/model/google_calendar_source.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/features/economy/providers/economy_providers.dart';
import 'package:task_manager/features/health/model/health_category.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/features/health/view/health_detail_screen.dart';
import 'package:task_manager/features/health/viewmodel/health_detail_viewmodel.dart';
import 'package:task_manager/features/roulette/model/roulette_outcome.dart';
import 'package:task_manager/features/roulette/providers/roulette_providers.dart';
import 'package:task_manager/features/roulette/view/roulette_settings_screen.dart';
import 'package:task_manager/features/todo/providers/todo_providers.dart';
import 'package:task_manager/features/todo/widgets/todo_drop_bar.dart';
import 'package:task_manager/features/user_settings/view/settings_screen.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/models/health_scores.dart';
import 'package:task_manager/screens/task_completion_screen.dart';
import 'package:task_manager/screens/task_editor_screen.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/health_panel.dart';
import 'package:task_manager/widgets/message_guard.dart';
import 'package:task_manager/widgets/quick_create_sheet.dart';
import 'package:task_manager/widgets/task_event_detail_sheet.dart';
import 'package:task_manager/widgets/user_status_panel.dart';
import 'package:task_manager/widgets/week_schedule_panel.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  static const int _initialPage = 5000;

  late DateTime _baseWeekStart;
  late DateTime _baseDay;
  late PageController _weekPageController;
  late PageController _dayPageController;
  CalendarViewMode _viewMode = CalendarViewMode.week;
  int _currentWeekPage = _initialPage;
  int _currentDayPage = _initialPage;
  int _weekStartDay = DateTime.monday;

  bool get _isOnToday => _viewMode == CalendarViewMode.week
      ? _currentWeekPage == _initialPage
      : _currentDayPage == _initialPage;

  DateTime get _currentWeekStart => _viewMode == CalendarViewMode.week
      ? _weekStartForPage(_currentWeekPage)
      : startOfWeek(_dayForPage(_currentDayPage), _weekStartDay);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    _weekStartDay = ref.read(userSettingsProvider).settings.weekStartDay;
    _baseWeekStart = startOfWeek(now, _weekStartDay);
    _baseDay = DateTime(now.year, now.month, now.day);
    _weekPageController = PageController(initialPage: _initialPage);
    _dayPageController = PageController(initialPage: _initialPage);
    // 起動時に「ダウンロード対象」のカレンダーの当該週を取り込む（idempotent）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoRollImportForCurrentWeek();
      // 累計タスク数を既存の完了タスクから一度だけバックフィル（ガード付き・冪等）。
      ref.read(rouletteRepositoryProvider).ensureCumulativeTaskCountBackfilled();
    });
  }

  Timer? _edgePagerTimer;
  Timer? _autoImportDebounceTimer;
  // 同じ週への重複importを抑止する直近キー。resumed時はforce=trueで無視。
  DateTime? _lastImportedWeekStart;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _edgePagerTimer?.cancel();
    _autoImportDebounceTimer?.cancel();
    _weekPageController.dispose();
    _dayPageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(healthDetailViewModelProvider.notifier).refreshForToday();
      // 復帰時は最新化したいのでガードを無視
      _autoRollImportForCurrentWeek(force: true);
    }
  }

  /// ダウンロード設定中のカレンダーについて、指定週ぶんを Firestore に取り込む。
  /// 既存タスクは upsert で更新されるため、起動／復帰のたびに呼んでも安全。
  /// [weekStart] 省略時は「今日基準の今週」。過去週は自動取り込み対象外。
  Future<void> _autoRollImportForCurrentWeek({
    DateTime? weekStart,
    bool force = false,
  }) async {
    final account = ref.read(currentGoogleAccountProvider);
    if (account == null) return;
    final dlMap = ref.read(calendarDownloadMapProvider);
    final calIds = dlMap[account.id];
    if (calIds == null || calIds.isEmpty) return;
    final target = weekStart ?? startOfWeek(DateTime.now(), _weekStartDay);

    // 過去週は自動対象外。明示的なDL導線（SnackBar）で対応する。
    final thisWeek = startOfWeek(DateTime.now(), _weekStartDay);
    if (target.isBefore(thisWeek)) return;

    if (!force && _lastImportedWeekStart == target) return;
    _lastImportedWeekStart = target;

    final vm = ref.read(calendarSyncViewModelProvider.notifier);
    final qMap = ref.read(calendarQuadrantMapProvider);
    for (final calId in calIds) {
      try {
        final defaultQ = qMap[account.id]?[calId] ?? 1;
        await vm.importWeek(
          calendarId: calId,
          weekStart: target,
          accountId: account.id,
          defaultQuadrant: defaultQ,
        );
      } catch (_) {
        // 個別失敗は他をブロックしない
      }
    }
  }

  // ── 日ビュードラッグ中の画面端ページング ─────────────────────

  void _handleDayDragPointerMove(PointerMoveEvent event) {
    if (!ref.read(isDraggingTaskProvider)) {
      _edgePagerTimer?.cancel();
      _edgePagerTimer = null;
      return;
    }
    const edgeWidth = 36.0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final x = event.position.dx;
    if (x < edgeWidth) {
      _armEdgePager(forward: false);
    } else if (x > screenWidth - edgeWidth) {
      _armEdgePager(forward: true);
    } else {
      _edgePagerTimer?.cancel();
      _edgePagerTimer = null;
    }
  }

  void _armEdgePager({required bool forward}) {
    if (_edgePagerTimer != null) return;
    _edgePagerTimer = Timer(const Duration(milliseconds: 500), () {
      _edgePagerTimer = null;
      if (!mounted) return;
      if (!ref.read(isDraggingTaskProvider)) return;
      if (forward) {
        _dayPageController.nextPage(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _dayPageController.previousPage(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 連続スワイプ時の余計な fetch を避けるため、最後に止まった週だけを取り込む。
  void _scheduleAutoImport(DateTime weekStart) {
    _autoImportDebounceTimer?.cancel();
    _autoImportDebounceTimer = Timer(const Duration(milliseconds: 400), () {
      _autoImportDebounceTimer = null;
      if (!mounted) return;
      _autoRollImportForCurrentWeek(weekStart: weekStart);
    });
  }

  DateTime _weekStartForPage(int index) =>
      _baseWeekStart.add(Duration(days: (index - _initialPage) * 7));

  DateTime _dayForPage(int index) =>
      _baseDay.add(Duration(days: index - _initialPage));

  /// カレンダー枠（または ToDo の estimatedMinutes）から見込時間を算出。
  int _predictedMinutesFor(CalendarTask task) {
    if (task.isTodo) return task.estimatedMinutes ?? 0;
    final s = task.start;
    final e = task.end;
    if (s != null && e != null) {
      final m = e.difference(s).inMinutes;
      if (m < 0) return 0;
      if (m > 24 * 60) return 24 * 60;
      return m;
    }
    return task.estimatedMinutes ?? 0;
  }

  /// 時間単価ベースで報酬を算出。単価未設定時は既存 reward にフォールバック。
  int _calcReward({
    required double hourlyRate,
    required int minutes,
    required int fallbackYen,
  }) {
    if (hourlyRate > 0 && minutes > 0) {
      return (hourlyRate * minutes / 60).round();
    }
    return fallbackYen;
  }

  Future<void> _openTask(CalendarTask task) async {
    final settings = ref.read(userSettingsProvider).settings;
    final predictedMinutes = _predictedMinutesFor(task);
    final expectedReward = _calcReward(
      hourlyRate: settings.hourlyRate,
      minutes: predictedMinutes,
      fallbackYen: task.rewardYen,
    );

    await showTaskEventDetailSheet(
      context: context,
      task: task,
      predictedMinutes: predictedMinutes,
      expectedRewardYen: expectedReward,
      calcReward: (minutes) {
        final s = ref.read(userSettingsProvider).settings;
        return _calcReward(
          hourlyRate: s.hourlyRate,
          minutes: minutes,
          fallbackYen: task.rewardYen,
        );
      },
      onSaveEdits: ({
        required title,
        required quadrant,
        required start,
        required end,
        required predictedMinutes,
        required actualMinutes,
      }) async {
        try {
          // promote は1回だけ。
          final taskId = await ref
              .read(calendarSyncViewModelProvider.notifier)
              .promoteRemoteTaskIfNeeded(task);
          if (taskId == null) {
            if (mounted) _showErrorSnackBar('保存に失敗しました（promote エラー）');
            return false;
          }
          await ref.read(calendarTaskSyncRepositoryProvider).updateTask(
            taskId: taskId,
            title: title,
            start: start,
            end: end,
          );
          await ref.read(calendarTaskSyncRepositoryProvider).updateQuadrant(
            taskId: taskId,
            urgency: quadrant.urgency,
            importance: quadrant.importance,
          );
          // 読み取り専用方針のため Google カレンダーへは書き戻さない（ローカルのみ更新）。
          // 進捗（実績分）も同じ保存操作で永続化（完了済みは対象外）。
          if (!task.isCompleted) {
            await ref.read(calendarTaskSyncRepositoryProvider).saveProgress(
              taskId: taskId,
              predictedMinutes: predictedMinutes,
              actualMinutes: actualMinutes,
            );
          }
          return true;
        } catch (e) {
          if (mounted) _showErrorSnackBar('保存に失敗しました: $e');
          return false;
        }
      },
      onTimerStart: () async {
        // リモート表示中なら DB に promote（保存済みなら no-op）
        await ref
            .read(calendarSyncViewModelProvider.notifier)
            .promoteRemoteTaskIfNeeded(task);
      },
      onPauseAndSave:
          ({required predictedMinutes, required actualMinutes}) async {
            if (task.isCompleted) return;
            final taskId = await ref
                .read(calendarSyncViewModelProvider.notifier)
                .promoteRemoteTaskIfNeeded(task);
            if (taskId == null) {
              if (mounted) {
                _showErrorSnackBar('タスクの保存に失敗したため、中断できませんでした');
              }
              return;
            }
            try {
              await ref
                  .read(calendarTaskSyncRepositoryProvider)
                  .saveProgress(
                    taskId: taskId,
                    predictedMinutes: predictedMinutes,
                    actualMinutes: actualMinutes,
                  );
            } catch (e) {
              if (mounted) _showErrorSnackBar('保存に失敗しました: $e');
              return;
            }
            if (!mounted) return;
            showAppSnackBar(
              context,
              const SnackBar(content: Text('一時中断しました（未了のまま保存）')),
            );
          },
      onRevert: () async {
        if (!task.isCompleted) return false;
        try {
          final result = await ref
              .read(economyRepositoryProvider)
              .revertTask(taskId: task.id, title: task.title);
          if (result.missingAmount) {
            if (mounted) _showErrorSnackBar('過去データの報酬額が未記録のため、未了に戻せません');
            return false;
          }
        } catch (e) {
          if (mounted) _showErrorSnackBar('未了への変更に失敗しました: $e');
          return false;
        }
        if (!mounted) return true;
        showAppSnackBar(context, const SnackBar(content: Text('未了に戻しました')));
        return true;
      },
      onComplete: ({required predictedMinutes, required actualMinutes}) async {
        final taskId = await ref
            .read(calendarSyncViewModelProvider.notifier)
            .promoteRemoteTaskIfNeeded(task);
        if (taskId == null) {
          if (mounted) {
            _showErrorSnackBar('タスクの保存に失敗したため、完了できませんでした');
          }
          return;
        }
        final latestSettings = ref.read(userSettingsProvider).settings;
        final minutesForReward = actualMinutes ?? predictedMinutes;
        final reward = _calcReward(
          hourlyRate: latestSettings.hourlyRate,
          minutes: minutesForReward,
          fallbackYen: task.rewardYen,
        );
        try {
          final result = await ref
              .read(economyRepositoryProvider)
              .completeTask(
                taskId: taskId,
                title: task.title,
                rewardYen: reward,
                predictedMinutes: predictedMinutes,
                actualMinutes: actualMinutes,
              );
          if (!result.applied) return;
          RouletteOutcome? outcome;
          try {
            outcome = await ref.read(rouletteServiceProvider).spin(
                  completionId: taskId,
                  settings: latestSettings,
                );
          } catch (_) {
            outcome = null;
          }
          if (!mounted) return;
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => TaskCompletionScreen(
                taskTitle: task.title,
                rewardYen: reward,
                balanceBeforeYen: result.balanceBeforeYen,
                balanceAfterYen: result.balanceAfterYen,
                outcome: outcome,
                cumulativeTaskCountBefore: result.cumulativeTaskCountBefore,
                cumulativeTaskCountAfter: result.cumulativeTaskCountAfter,
              ),
            ),
          );
        } catch (e) {
          if (mounted) _showErrorSnackBar('完了状態の保存に失敗しました: $e');
          return;
        }
      },
      onEdit: () {
        if (!mounted) return;
        Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) =>
                TaskEditorScreen(mode: TaskEditorMode.edit, initial: task),
          ),
        );
      },
      onDuplicate: () {
        if (!mounted) return;
        final baseStart = task.end ?? DateTime.now();
        Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => TaskEditorScreen(
              mode: TaskEditorMode.create,
              initial: task,
              initialStart: baseStart,
            ),
          ),
        );
      },
      onDelete: () async {
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('削除確認'),
            content: Text('「${task.title}」を削除しますか？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('削除'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        final vm = ref.read(calendarSyncViewModelProvider.notifier);
        final ok = await vm.deleteTask(task);
        if (!mounted) return;
        if (ok) {
          showAppSnackBar(context, const SnackBar(content: Text('削除しました')));
        } else {
          final msg = ref.read(calendarSyncViewModelProvider).errorMessage;
          _showErrorSnackBar(msg ?? '削除に失敗しました');
          vm.clearError();
        }
      },
    );
  }

  Future<void> _signOut() async {
    await ref.read(authRepositoryProvider).signOut();
  }

  // ── 空スロットタップでの予定追加 ───────────────────────────────

  Future<void> _handleEmptyTap(DateTime initialStart) async {
    final result = await showModalBottomSheet<QuickCreateResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => QuickCreateSheet(initialStart: initialStart),
    );
    if (result == null || !mounted) return;
    final (:title, :durationMinutes, :quadrant) = result;
    final end = initialStart.add(Duration(minutes: durationMinutes));
    final vm = ref.read(calendarSyncViewModelProvider.notifier);
    final success = await vm.createTask(
      title: title,
      start: initialStart,
      end: end,
      urgency: quadrant.urgency,
      importance: quadrant.importance,
    );
    if (!mounted) return;
    if (success) {
      showAppSnackBar(context, const SnackBar(content: Text('予定を追加しました')));
    } else {
      final errorMsg = ref.read(calendarSyncViewModelProvider).errorMessage;
      _showErrorSnackBar(errorMsg ?? '追加に失敗しました');
      vm.clearError();
    }
  }

  // ── カレンダー連携フロー（表示ON/OFF管理） ──────────────────────

  /// 「取得」ボタン押下時：
  /// 1. Google アカウントにサインイン（初回 or アクティブ未設定時のみピッカー）
  /// 2. そのアカウントのカレンダー一覧を取得
  /// 3. 可視性チェックボックスのダイアログを表示
  ///
  /// 注意：Firestore へのイベント保存はここでは行わない（仕様6）。
  /// 表示は [remoteWeekEventsProvider] が自動で取得する。
  Future<void> _handleImport(DateTime weekStart) async {
    await _openCalendarChooser(weekStart);
  }

  Future<void> _openCalendarChooser(
    DateTime weekStart, {
    bool forceAccountPicker = false,
  }) async {
    final repo = ref.read(googleCalendarRepositoryProvider);
    final vm = ref.read(calendarSyncViewModelProvider.notifier);

    // アクティブアカウントの確保（無ければピッカー、強制フラグならピッカー再呼び出し）
    GoogleAccountInfo? account = ref.read(currentGoogleAccountProvider);
    try {
      if (account == null || forceAccountPicker) {
        account = await repo.signInWithPicker();
      } else {
        // 現アカウントが生きていればそのまま
        final resolved = await repo.getCurrentAccount();
        account = resolved ?? await repo.signInWithPicker();
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(
        'アカウント認証に失敗しました: $e',
        retry: () => _openCalendarChooser(
          weekStart,
          forceAccountPicker: forceAccountPicker,
        ),
      );
      return;
    }
    if (account == null) return; // ユーザーキャンセル
    ref.read(currentGoogleAccountProvider.notifier).set(account);

    // 可視性・象限をロード（初期化時に未ロードの場合に備えて）
    await Future.wait([
      ref.read(calendarVisibilityProvider.future),
      ref.read(calendarQuadrantProvider.future),
    ]);

    // カレンダー一覧取得
    final calendars = await vm.loadCalendars();
    if (!mounted) return;
    final state = ref.read(calendarSyncViewModelProvider);
    if (state.errorMessage != null) {
      _showErrorSnackBar(
        state.errorMessage!,
        retry: () => _openCalendarChooser(weekStart),
      );
      vm.clearError();
      return;
    }
    if (calendars.isEmpty) {
      showAppSnackBar(
        context,
        const SnackBar(content: Text('カレンダーが見つかりませんでした')),
      );
      return;
    }

    await _showCalendarVisibilityDialog(
      account: account,
      calendars: calendars,
      weekStart: weekStart,
      onSwitchAccount: () async {
        Navigator.of(context).pop();
        await _openCalendarChooser(weekStart, forceAccountPicker: true);
      },
    );
  }

  Future<void> _showCalendarVisibilityDialog({
    required GoogleAccountInfo account,
    required List<GoogleCalendarSource> calendars,
    required DateTime weekStart,
    required VoidCallback onSwitchAccount,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('表示するカレンダー'),
              const SizedBox(height: 2),
              Text(
                account.email,
                style: Theme.of(ctx).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // カラムヘッダー（目アイコン＝表示／DLアイコン＝タスク化）
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: _kCalToggleColWidth,
                        child: Center(
                          child: Icon(
                            Icons.visibility_outlined,
                            size: 18,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: _kCalToggleColWidth,
                        child: Center(
                          child: Icon(
                            Icons.cloud_download_outlined,
                            size: 18,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Expanded(child: SizedBox.shrink()),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: Consumer(
                    builder: (ctx, ref, _) {
                      final visMap = ref.watch(calendarVisibilityMapProvider);
                      final dlMap = ref.watch(calendarDownloadMapProvider);
                      final qMap = ref.watch(calendarQuadrantMapProvider);
                      final visible = visMap[account.id] ?? const <String>{};
                      final downloaded = dlMap[account.id] ?? const <String>{};
                      final quadrants =
                          qMap[account.id] ?? const <String, int>{};
                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: calendars.length,
                        itemBuilder: (ctx, i) {
                          final cal = calendars[i];
                          final hex = cal.colorHex;
                          final parsed = hex == null ? null : _parseHex(hex);
                          final isVisible = visible.contains(cal.id);
                          final isDownloaded = downloaded.contains(cal.id);
                          final qNum = quadrants[cal.id] ?? 1;
                          return _CalendarRow(
                            calendar: cal,
                            colorDot: parsed,
                            isVisible: isVisible,
                            isDownloaded: isDownloaded,
                            quadrantNumber: qNum,
                            onVisibilityChanged: (on) async {
                              await ref
                                  .read(calendarVisibilityProvider.notifier)
                                  .setVisible(
                                    accountId: account.id,
                                    calendarId: cal.id,
                                    visible: on,
                                  );
                            },
                            onDownloadChanged: (on) async {
                              await _handleDownloadToggle(
                                accountId: account.id,
                                calendar: cal,
                                weekStart: weekStart,
                                turnOn: on,
                                wasVisible: isVisible,
                              );
                            },
                            onQuadrantTap: () async {
                              final scheme = Theme.of(ctx).colorScheme;
                              final selected = await showMenu<int>(
                                context: ctx,
                                position: RelativeRect.fromLTRB(
                                  MediaQuery.sizeOf(ctx).width - 60,
                                  0,
                                  0,
                                  0,
                                ),
                                items: List.generate(4, (j) {
                                  final n = j + 1;
                                  final q = QuadrantX.fromNumber(n);
                                  final isCurrent = n == qNum;
                                  return PopupMenuItem<int>(
                                    value: n,
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
                                          Icon(
                                            Icons.check,
                                            size: 16,
                                            color: scheme.primary,
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }),
                              );
                              if (selected == null || selected == qNum) return;
                              await ref
                                  .read(calendarQuadrantProvider.notifier)
                                  .setQuadrant(
                                    accountId: account.id,
                                    calendarId: cal.id,
                                    quadrantNumber: selected,
                                  );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: onSwitchAccount,
              icon: const Icon(Icons.switch_account, size: 18),
              label: const Text('別のアカウント'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  /// ダウンロードチェックON/OFF時のハンドラ。
  /// ON：当該週を `importWeek` で取り込み → DLフラグON。表示が未ONなら自動でON。
  /// OFF：確認ダイアログ → OKで `deleteTasksByCalendarInWeek` → DLフラグOFF。
  Future<void> _handleDownloadToggle({
    required String accountId,
    required GoogleCalendarSource calendar,
    required DateTime weekStart,
    required bool turnOn,
    required bool wasVisible,
  }) async {
    if (turnOn) {
      final qMap = ref.read(calendarQuadrantMapProvider);
      final defaultQ = qMap[accountId]?[calendar.id] ?? 1;
      final ok = await ref
          .read(calendarSyncViewModelProvider.notifier)
          .importWeek(
            calendarId: calendar.id,
            weekStart: weekStart,
            accountId: accountId,
            defaultQuadrant: defaultQ,
          );
      if (!ok) {
        final msg =
            ref.read(calendarSyncViewModelProvider).errorMessage ??
            '取り込みに失敗しました';
        ref.read(calendarSyncViewModelProvider.notifier).clearError();
        if (mounted) _showErrorSnackBar(msg);
        return;
      }
      await ref
          .read(calendarDownloadProvider.notifier)
          .setDownloaded(
            accountId: accountId,
            calendarId: calendar.id,
            downloaded: true,
          );
      // タスクが見えないと不便なため、表示も自動でON
      if (!wasVisible) {
        await ref
            .read(calendarVisibilityProvider.notifier)
            .setVisible(
              accountId: accountId,
              calendarId: calendar.id,
              visible: true,
            );
      }
      return;
    }
    // OFF：確認
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取り込みを解除しますか？'),
        content: Text(
          '「${calendar.name}」の未着手の取り込みタスクを削除します'
          '（完了済み・実績入力済み・ToDo化済みは残ります）。続行しますか？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(calendarTaskSyncRepositoryProvider)
          .deleteTasksByCalendarInWeek(
            calendarId: calendar.id,
            weekStartLocal: weekStart,
          );
      await ref
          .read(calendarDownloadProvider.notifier)
          .setDownloaded(
            accountId: accountId,
            calendarId: calendar.id,
            downloaded: false,
          );
    } catch (e) {
      if (mounted) _showErrorSnackBar('削除に失敗しました: $e');
    }
  }

  static Color? _parseHex(String hex) {
    var c = hex.replaceAll('#', '').trim();
    if (c.length == 6) c = 'FF$c';
    if (c.length != 8) return null;
    final v = int.tryParse(c, radix: 16);
    return v == null ? null : Color(v);
  }

  void _showErrorSnackBar(String message, {VoidCallback? retry}) {
    showAppSnackBar(
      context,
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 8),
        action: retry != null
            ? SnackBarAction(
                label: '再試行',
                textColor: Theme.of(context).colorScheme.onError,
                onPressed: retry,
              )
            : null,
      ),
    );
  }

  void _jumpToToday() {
    if (_viewMode == CalendarViewMode.week) {
      _weekPageController.jumpToPage(_initialPage);
    } else {
      _dayPageController.jumpToPage(_initialPage);
    }
  }

  void _handleViewModeChange(CalendarViewMode mode) {
    setState(() => _viewMode = mode);
  }

  // ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).asData?.value;
    final syncState = ref.watch(calendarSyncViewModelProvider);

    // 週の始まり設定の変更を追従
    ref.listen<int>(
      userSettingsProvider.select((s) => s.settings.weekStartDay),
      (prev, next) {
        if (!mounted || prev == next) return;
        setState(() {
          _weekStartDay = next;
          _baseWeekStart = startOfWeek(DateTime.now(), next);
        });
        // 週境界が変わるので重複ガードをリセット
        _lastImportedWeekStart = null;
      },
    );

    // DLチェック設定が変わったら次回スワイプで再取り込みを許可
    ref.listen<Map<String, Set<String>>>(calendarDownloadMapProvider, (
      prev,
      next,
    ) {
      if (prev == next) return;
      _lastImportedWeekStart = null;
    });

    // アカウント切替時もリセット
    ref.listen<GoogleAccountInfo?>(currentGoogleAccountProvider, (prev, next) {
      if (prev?.id == next?.id) return;
      _lastImportedWeekStart = null;
    });

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            tooltip: 'メニュー',
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('人生ゲーム化'),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'home_fab',
        tooltip: '予定を追加',
        onPressed: () {
          Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) =>
                  const TaskEditorScreen(mode: TaskEditorMode.create),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(user?.displayName ?? 'ユーザー'),
              accountEmail: Text(user?.email ?? ''),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  (user?.displayName?.isNotEmpty == true
                          ? user!.displayName![0]
                          : user?.email?[0] ?? '?')
                      .toUpperCase(),
                  style: TextStyle(
                    fontSize: 24,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.auto_stories_outlined),
              title: const Text('冒険の記録'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdventureLogScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.casino_outlined),
              title: const Text('ルーレット設定'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const RouletteSettingsScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('ログアウト'),
              onTap: () async {
                Navigator.of(context).pop();
                await _signOut();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('設定'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: MessageGuard(
        child: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
                child: Column(
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Expanded(child: UserStatusPanel()),
                          const SizedBox(width: 10),
                          const Expanded(child: _HealthPanelConnector()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ScheduleHeaderBar(
                              viewMode: _viewMode,
                              isOnToday: _isOnToday,
                              onViewModeChanged: _handleViewModeChange,
                              onJumpToToday: _jumpToToday,
                              onImportFromCalendar: () =>
                                  _handleImport(_currentWeekStart),
                              isImporting: syncState.isLoading,
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: IndexedStack(
                                index: _viewMode == CalendarViewMode.week ? 0 : 1,
                                children: [
                                  PageView.builder(
                                    controller: _weekPageController,
                                    onPageChanged: (p) {
                                      final prevWs = _weekStartForPage(
                                        _currentWeekPage,
                                      );
                                      final newWs = _weekStartForPage(p);
                                      setState(() => _currentWeekPage = p);
                                      if (prevWs != newWs) {
                                        _scheduleAutoImport(newWs);
                                      }
                                    },
                                    itemBuilder: (context, index) {
                                      final ws = _weekStartForPage(index);
                                      final visibleDays = List.generate(
                                        7,
                                        (i) => ws.add(Duration(days: i)),
                                      );
                                      return _SchedulePage(
                                        visibleDays: visibleDays,
                                        onTaskTap: _openTask,
                                        onEmptyTap: _handleEmptyTap,
                                      );
                                    },
                                  ),
                                  Listener(
                                    onPointerMove: _handleDayDragPointerMove,
                                    child: PageView.builder(
                                      controller: _dayPageController,
                                      onPageChanged: (p) {
                                        final prevWs = startOfWeek(
                                          _dayForPage(_currentDayPage),
                                          _weekStartDay,
                                        );
                                        final newWs = startOfWeek(
                                          _dayForPage(p),
                                          _weekStartDay,
                                        );
                                        setState(() => _currentDayPage = p);
                                        if (prevWs != newWs) {
                                          _scheduleAutoImport(newWs);
                                        }
                                      },
                                      itemBuilder: (context, index) {
                                        final day = _dayForPage(index);
                                        return _SchedulePage(
                                          visibleDays: [day],
                                          onTaskTap: _openTask,
                                          onEmptyTap: _handleEmptyTap,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: TodoDropBar(
                  onSwitchToTodo: () {
                    ref.read(mainTabIndexProvider.notifier).set(1);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 可変日数（1〜7日）のパネル本体。対応週のタスクをwatch、非表示カレンダーと
/// visibleDays の範囲でフィルタして WeekSchedulePanel に渡す。ヘッダーは親で描画。
class _SchedulePage extends ConsumerWidget {
  const _SchedulePage({
    required this.visibleDays,
    required this.onTaskTap,
    required this.onEmptyTap,
  });

  final List<DateTime> visibleDays;
  final ValueChanged<CalendarTask> onTaskTap;
  final ValueChanged<DateTime> onEmptyTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStartDay = ref.watch(
      userSettingsProvider.select((s) => s.settings.weekStartDay),
    );
    final weekStart = startOfWeek(visibleDays.first, weekStartDay);

    // Firestore 保存済みタスク
    final savedAsync = ref.watch(weekTasksProvider(weekStart));
    final savedTasks = savedAsync.asData?.value ?? const <CalendarTask>[];

    // リモート（Google Calendar）イベント：表示のみ、DB未保存
    final remoteAsync = ref.watch(remoteWeekEventsProvider(weekStart));
    final remoteTasks = remoteAsync.asData?.value ?? const <CalendarTask>[];

    // リモート取得エラー時に SnackBar + 再試行導線
    ref.listen<AsyncValue<List<CalendarTask>>>(
      remoteWeekEventsProvider(weekStart),
      (prev, next) {
        if (next.hasError && (prev == null || !prev.hasError)) {
          showAppSnackBar(
            context,
            SnackBar(
              content: Text('Google カレンダーの取得に失敗: ${next.error}'),
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: '再試行',
                onPressed: () =>
                    ref.invalidate(remoteWeekEventsProvider(weekStart)),
              ),
            ),
          );
        }
      },
    );

    final account = ref.watch(currentGoogleAccountProvider);
    final visibilityMap = ref.watch(calendarVisibilityMapProvider);

    final dayKeys = visibleDays
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();

    bool inRange(CalendarTask t) {
      final start = t.start;
      if (start == null) return false;
      return dayKeys.contains(DateTime(start.year, start.month, start.day));
    }

    bool isCalendarVisible(CalendarTask t) {
      final key = ExternalCalendarKey.tryParse(t.externalCalendarId);
      if (key == null) return true; // 手動タスク
      // 3要素形式（accountId入り）はそのアカウントの可視集合を参照。
      // 旧2要素形式は暫定で currentAccount の可視集合を参照。
      final accountId = key.accountId ?? account?.id;
      if (accountId == null) return true;
      return visibilityMap[accountId]?.contains(key.calendarId) ?? false;
    }

    // 保存済み：ToDo除外 + 可視カレンダー + 週内
    final filteredSaved = savedTasks.where((t) {
      if (t.isTodo) return false;
      if (!isCalendarVisible(t)) return false;
      return inRange(t);
    }).toList();

    // リモート：既に保存されている externalCalendarId は除外（保存側を優先）
    final savedExtIds = filteredSaved
        .map((t) => t.externalCalendarId)
        .whereType<String>()
        .toSet();
    final filteredRemote = remoteTasks.where((t) {
      final ext = t.externalCalendarId;
      if (ext != null && savedExtIds.contains(ext)) return false;
      return inRange(t);
    }).toList();

    final visibleTasks = [...filteredSaved, ...filteredRemote];
    final taskIds = filteredSaved.map((t) => t.id).toSet();

    void handleTap(CalendarTask t) {
      if (taskIds.contains(t.id)) {
        onTaskTap(t);
      }
      // 表示専用イベントは何もしない（移動を試みた時だけ案内を出す）
    }

    return WeekSchedulePanel(
      visibleDays: visibleDays,
      tasks: visibleTasks,
      onTaskTap: handleTap,
      onEmptyTap: onEmptyTap,
      onReadOnlyMoveAttempt: (t) =>
          _showDownloadPrompt(context, ref, t, weekStart),
      taskIds: taskIds,
    );
  }

  /// 表示専用（未ダウンロード）の Google イベントを動かそうとしたときの導線。
  /// SnackBar で「ダウンロード」ボタンを出し、押すとそのカレンダーの当該週を
  /// importWeek + DLフラグON してタスク化する。
  void _showDownloadPrompt(
    BuildContext context,
    WidgetRef ref,
    CalendarTask task,
    DateTime weekStart,
  ) {
    final key = ExternalCalendarKey.tryParse(task.externalCalendarId);
    final canDownload = key != null;
    showAppSnackBar(
      context,
      SnackBar(
        showCloseIcon: true,
        duration: const Duration(seconds: 8),
        content: const Text('表示専用なので動かせません。ダウンロードするとタスクとして管理・移動できます。'),
        action: !canDownload
            ? null
            : SnackBarAction(
                label: 'ダウンロード',
                onPressed: () async {
                  final account = ref.read(currentGoogleAccountProvider);
                  final accountId = key.accountId ?? account?.id;
                  if (accountId == null) return;
                  final qMap = ref.read(calendarQuadrantMapProvider);
                  final defaultQ = qMap[accountId]?[key.calendarId] ?? 1;
                  final ok = await ref
                      .read(calendarSyncViewModelProvider.notifier)
                      .importWeek(
                        calendarId: key.calendarId,
                        weekStart: weekStart,
                        accountId: accountId,
                        defaultQuadrant: defaultQ,
                      );
                  if (!ok) return;
                  await ref
                      .read(calendarDownloadProvider.notifier)
                      .setDownloaded(
                        accountId: accountId,
                        calendarId: key.calendarId,
                        downloaded: true,
                      );
                },
              ),
      ),
    );
  }
}

/// カレンダー可視性ダイアログのチェックボックス1列の幅。
const double _kCalToggleColWidth = 36;

class _CalendarRow extends StatelessWidget {
  const _CalendarRow({
    required this.calendar,
    required this.colorDot,
    required this.isVisible,
    required this.isDownloaded,
    required this.quadrantNumber,
    required this.onVisibilityChanged,
    required this.onDownloadChanged,
    required this.onQuadrantTap,
  });

  final GoogleCalendarSource calendar;
  final Color? colorDot;
  final bool isVisible;
  final bool isDownloaded;
  final int quadrantNumber;
  final ValueChanged<bool> onVisibilityChanged;
  final ValueChanged<bool> onDownloadChanged;
  final VoidCallback onQuadrantTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = QuadrantX.fromNumber(quadrantNumber);
    final qColor = q.accentColor(scheme);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          SizedBox(
            width: _kCalToggleColWidth,
            child: Center(
              child: Checkbox(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                value: isVisible,
                // ダウンロードON中は表示ON固定・ロック（先に取り込み解除が必要）
                onChanged: isDownloaded
                    ? null
                    : (v) => onVisibilityChanged(v == true),
              ),
            ),
          ),
          SizedBox(
            width: _kCalToggleColWidth,
            child: Center(
              child: Checkbox(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                value: isDownloaded,
                onChanged: (v) => onDownloadChanged(v == true),
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (calendar.isPrimary) ...[
            const Icon(Icons.star, size: 14, color: Colors.amber),
            const SizedBox(width: 4),
          ],
          Expanded(child: Text(calendar.name, overflow: TextOverflow.ellipsis)),
          GestureDetector(
            onTap: onQuadrantTap,
            child: Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: qColor,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant, width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 今日の健康ログ（VM 状態）を HealthPanel 用の HealthScores に変換し、
/// タップで健康詳細画面へ遷移する。
class _HealthPanelConnector extends ConsumerWidget {
  const _HealthPanelConnector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(healthDetailViewModelProvider).log;
    final settings = ref.watch(userSettingsProvider).settings;
    final scores = HealthScores(
      meal: HealthCategory.meal.level(log, settings),
      sleep: HealthCategory.sleep.level(log, settings),
      exercise: HealthCategory.exercise.level(log, settings),
      meditation: HealthCategory.meditation.level(log, settings),
    );
    return HealthPanel(
      scores: scores,
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const HealthDetailScreen()),
      ),
    );
  }
}
