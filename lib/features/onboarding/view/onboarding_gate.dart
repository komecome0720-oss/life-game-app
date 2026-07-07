import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/onboarding/onboarding_keys.dart';
import 'package:task_manager/features/onboarding/providers/onboarding_providers.dart';
import 'package:task_manager/features/onboarding/view/onboarding_flow_screen.dart';
import 'package:task_manager/features/onboarding/widgets/coach_mark_overlay.dart';
import 'package:task_manager/features/todo/providers/todo_providers.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/utils/center_flash.dart';

enum _Phase { wizard, coachMarks, done }

/// [child]（＝ホーム画面本体）を包み、初回オンボーディング（ウィザード→コーチマーク）の
/// 表示・非表示を切り替えるゲート。
///
/// - ロード中: スピナー（_AuthGate のローディングと同じ見た目）。
/// - ロード完了時に1回だけ初期フェーズを決定する:
///   - ロードエラー時（errorMessage != null）は安全側に倒して done（fail-open）。
///     オフライン初回起動等でデフォルト値のまま wizard を誤表示しないため。
///   - それ以外は settings.onboardingCompleted の値で wizard / done を決める。
/// - 設定画面の「使い方をもう一度見る」は [onboardingReplayProvider] をインクリメントし、
///   それを検知してコーチマークのみ再生する（ウィザードの入力ステップは出さない）。
class OnboardingGate extends ConsumerStatefulWidget {
  const OnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends ConsumerState<OnboardingGate> {
  _Phase? _phase;
  int _lastReplayToken = 0;

  /// coachMarks フェーズに入った直後は対象 GlobalKey の RenderBox がまだ
  /// レイアウトされていないことがあるため、最初のフレーム確定後に1度だけ
  /// 再ビルドしてくり抜き矩形を正しく計算し直す（CoachMarkOverlay は
  /// targetRect が取れない間も中央表示でフォールバックするためクラッシュはしない）。
  ///
  /// 「使い方をもう一度見る」からの再生時は設定画面からの popUntil による
  /// 画面遷移アニメーション（iOSではparallaxで裏の画面も一時的にズレて見える）が
  /// 進行中にこの直後の再ビルドが走ってしまい、ズレた位置のまま固定されることがある。
  /// そのため遷移アニメーションが完了するタイミングでもう一度再計算する。
  void _scheduleCoachMarkRelayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _phase == _Phase.coachMarks) setState(() {});
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && _phase == _Phase.coachMarks) setState(() {});
    });
  }

  List<CoachMarkStep> get _coachMarkSteps => [
        CoachMarkStep(
          targetKey: OnboardingKeys.userStatusPanel,
          title: 'ステータス',
          body: '今のあなたの状態。レベル・所持金・時間単価はここで確認。タップでプロフィール設定が開くよ',
        ),
        CoachMarkStep(
          targetKey: OnboardingKeys.healthPanel,
          title: '健康管理',
          body: '野菜・果物・運動・睡眠・瞑想を毎日記録。100点で時間単価3時間分のお金がもらえる。タップで記録画面へ',
        ),
        CoachMarkStep(
          targetKey: OnboardingKeys.weekSchedule,
          title: '週間スケジュール',
          body: 'ここに予定（クエスト）が並ぶ。右下の＋ボタンか予定がないところをタップして予定を追加、終わったらタップして完了報告するとお金がもらえるよ。右上の「取得」ボタンでgoogleカレンダーから予定を取り込めるよ',
        ),
        CoachMarkStep(
          targetKey: OnboardingKeys.todoTab,
          title: 'ToDoタブ',
          body: '重要度で整理できるtodoリスト。タスクを長押しして画面上に移動するとカレンダーとtodoを自由に行き来できるよ',
        ),
        CoachMarkStep(
          targetKey: OnboardingKeys.wishTab,
          title: '欲しいものタブ',
          body: '貯めたお金の使い道。欲しいものを登録して、貯まったら交換しよう',
        ),
        CoachMarkStep(
          targetKey: OnboardingKeys.menuButton,
          title: 'メニュー',
          body: '冒険の記録（履歴）、ルーレット設定、アプリの設定はここから。今の説明は設定画面から何回でも見れるよ',
        ),
      ];

  void _startCoachMarksReplay() {
    ref.read(mainTabIndexProvider.notifier).set(0);
    setState(() => _phase = _Phase.coachMarks);
    _scheduleCoachMarkRelayout();
  }

  Future<void> _finishCoachMarks({required bool isReplay}) async {
    final alreadyCompleted =
        ref.read(userSettingsProvider).settings.onboardingCompleted;
    if (!alreadyCompleted) {
      if (!isReplay && mounted) {
        showCenterFlash(context, '冒険のはじまり！');
      }
      await ref.read(userSettingsProvider.notifier).saveOnboardingCompleted();
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.done);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userSettingsProvider);

    ref.listen<int>(onboardingReplayProvider, (prev, next) {
      if (prev != null && next != prev) {
        _lastReplayToken = next;
        _startCoachMarksReplay();
      }
    });

    if (state.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // ロード完了後、最初の1回だけ初期フェーズを決定する。
    _phase ??= state.errorMessage != null
        ? _Phase.done
        : (state.settings.onboardingCompleted ? _Phase.done : _Phase.wizard);

    switch (_phase!) {
      case _Phase.wizard:
        return OnboardingFlowScreen(
          onFinished: () {
            setState(() => _phase = _Phase.coachMarks);
            _scheduleCoachMarkRelayout();
          },
        );
      case _Phase.coachMarks:
        final isReplay = _lastReplayToken != 0;
        return Stack(
          children: [
            widget.child,
            CoachMarkOverlay(
              steps: _coachMarkSteps,
              onFinished: () => _finishCoachMarks(isReplay: isReplay),
              onSkipAll: () => _finishCoachMarks(isReplay: isReplay),
            ),
          ],
        );
      case _Phase.done:
        return widget.child;
    }
  }
}
