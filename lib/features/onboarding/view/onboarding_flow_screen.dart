import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/onboarding/widgets/concept_page.dart';
import 'package:task_manager/features/onboarding/widgets/health_goal_form.dart';
import 'package:task_manager/features/onboarding/widgets/status_form.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/message_guard.dart';

/// オンボーディングウィザード本体（①コンセプト→②ステータス入力→③健康目標入力）。
///
/// [replayOnly] が true の場合は①のみを表示する（設定画面からの再閲覧用）。
/// 各ステップの保存は UserSettingsViewModel を直接呼ぶ（ステップ自体は純粋ウィジェット）。
class OnboardingFlowScreen extends ConsumerStatefulWidget {
  const OnboardingFlowScreen({
    super.key,
    required this.onFinished,
    this.replayOnly = false,
  });

  /// 全ステップ終了（またはreplay版の①終了）時に呼ばれる。
  final VoidCallback onFinished;

  /// true の場合はコンセプトページのみを表示するreplayモード。
  final bool replayOnly;

  @override
  ConsumerState<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

enum _Step { concept, status, healthGoal }

class _OnboardingFlowScreenState extends ConsumerState<OnboardingFlowScreen> {
  _Step _step = _Step.concept;
  bool _saving = false;

  Future<void> _handleStatusSubmit(
    String displayName,
    int monthlyBudget,
    int monthlyQuestDays,
    int dailyQuestMinutes,
  ) async {
    if (_saving) return;
    setState(() => _saving = true);
    final vm = ref.read(userSettingsProvider.notifier);
    final current = ref.read(userSettingsProvider).settings;
    vm.update(
      current.copyWith(
        displayName: displayName,
        monthlyBudget: monthlyBudget,
        monthlyQuestDays: monthlyQuestDays,
        dailyQuestMinutes: dailyQuestMinutes,
      ),
    );
    final success = await vm.save();
    if (!mounted) return;
    setState(() => _saving = false);
    if (!success) {
      final errorMsg = ref.read(userSettingsProvider).errorMessage;
      showAppSnackBar(
        context,
        SnackBar(
          content: Text(errorMsg ?? '保存に失敗しました'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    setState(() => _step = _Step.healthGoal);
  }

  Future<void> _handleHealthGoalSubmit(
    int mealGoalGrams,
    int exerciseGoalMinutes,
    int sleepGoalHours,
    int sleepGoalMinutesExtra,
    int meditationGoalMinutes,
  ) async {
    if (_saving) return;
    setState(() => _saving = true);
    final vm = ref.read(userSettingsProvider.notifier);
    final current = ref.read(userSettingsProvider).settings;
    vm.update(
      current.copyWith(
        mealGoalGrams: mealGoalGrams,
        exerciseGoalMinutes: exerciseGoalMinutes,
        sleepGoalHours: sleepGoalHours,
        sleepGoalMinutesExtra: sleepGoalMinutesExtra,
        meditationGoalMinutes: meditationGoalMinutes,
      ),
    );
    final success = await vm.save();
    if (!mounted) return;
    setState(() => _saving = false);
    if (!success) {
      final errorMsg = ref.read(userSettingsProvider).errorMessage;
      showAppSnackBar(
        context,
        SnackBar(
          content: Text(errorMsg ?? '保存に失敗しました'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(userSettingsProvider).settings;

    Widget child;
    switch (_step) {
      case _Step.concept:
        child = ConceptPage(
          buttonLabel: widget.replayOnly ? '画面の説明を見る' : 'はじめる',
          onStart: () {
            if (widget.replayOnly) {
              widget.onFinished();
              return;
            }
            setState(() => _step = _Step.status);
          },
        );
      case _Step.status:
        child = _saving
            ? const Center(child: CircularProgressIndicator())
            : StatusForm(
                initial: StatusFormInitial(
                  displayName: settings.displayName,
                  monthlyBudget: settings.monthlyBudget,
                  monthlyQuestDays: settings.monthlyQuestDays,
                  dailyQuestMinutes: settings.dailyQuestMinutes,
                ),
                onSubmit: _handleStatusSubmit,
              );
      case _Step.healthGoal:
        child = _saving
            ? const Center(child: CircularProgressIndicator())
            : HealthGoalForm(
                initial: HealthGoalFormInitial(
                  mealGoalGrams: settings.mealGoalGrams,
                  exerciseGoalMinutes: settings.exerciseGoalMinutes,
                  sleepGoalHours: settings.sleepGoalHours,
                  sleepGoalMinutesExtra: settings.sleepGoalMinutesExtra,
                  meditationGoalMinutes: settings.meditationGoalMinutes,
                ),
                onSubmit: _handleHealthGoalSubmit,
                onSkip: widget.onFinished,
              );
    }

    return Scaffold(
      body: MessageGuard(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(key: ValueKey(_step), child: child),
        ),
      ),
    );
  }
}
