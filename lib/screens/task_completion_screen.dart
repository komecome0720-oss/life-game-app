import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:task_manager/features/prediction_accuracy/model/prediction_accuracy_config.dart';
import 'package:task_manager/features/roulette/model/reward_config.dart';
import 'package:task_manager/features/roulette/model/roulette_outcome.dart';
import 'package:task_manager/features/roulette/widgets/roulette_board.dart';
import 'package:task_manager/theme/app_tokens.dart';
import 'package:task_manager/widgets/message_guard.dart';
import 'package:task_manager/widgets/reward_burst.dart';

class TaskCompletionScreen extends StatefulWidget {
  const TaskCompletionScreen({
    super.key,
    required this.taskTitle,
    required this.rewardYen,
    this.balanceBeforeYen,
    this.balanceAfterYen,
    this.outcome,
    this.cumulativeTaskCountBefore,
    this.cumulativeTaskCountAfter,
    this.predictedMinutes,
    this.actualMinutes,
  });

  final String taskTitle;
  final int rewardYen;

  /// 所持金の変化を表示するときのみ指定（例: ￥２０５４０→２０５９０）。
  final int? balanceBeforeYen;
  final int? balanceAfterYen;

  /// ルーレット抽選の結果（演出に使用）。null の場合は盤面を出さない。
  final RouletteOutcome? outcome;

  /// レベル進捗表示用の累計タスク数（完了前後）。
  final int? cumulativeTaskCountBefore;
  final int? cumulativeTaskCountAfter;

  /// 今回のタスクの予測・実績時間（分）。両方揃っている場合のみ今回の精度を表示する。
  final int? predictedMinutes;
  final int? actualMinutes;

  @override
  State<TaskCompletionScreen> createState() => _TaskCompletionScreenState();
}

class _TaskCompletionScreenState extends State<TaskCompletionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinCtrl;
  late final Animation<double> _spin;
  late final List<RouletteCell> _cells;
  late final bool _leveledUp;
  late final int? _leveledUpLevel;
  late final String? _leveledUpTitle;
  Timer? _spinStartTimer;
  Timer? _levelBurstTimer;
  Timer? _levelBurstHideTimer;
  double _targetRotation = 0;
  _RoulettePhase _phase = _RoulettePhase.waiting;
  bool _showLevelBurst = false;

  bool get _hasBoard => widget.outcome?.probabilities != null;

  int? get _thisTaskErrorPercent {
    final predicted = widget.predictedMinutes;
    final actual = widget.actualMinutes;
    if (predicted == null || predicted <= 0 || actual == null) return null;
    final error = PredictionAccuracyConfig.errorFor(
      predictedMinutes: predicted,
      actualMinutes: actual,
    );
    return (error * 100).round();
  }

  /// 今回の予測との差分（分）。表示は分を主役にする（確定仕様14）。
  int? get _thisTaskDiffMinutes {
    final predicted = widget.predictedMinutes;
    final actual = widget.actualMinutes;
    if (predicted == null || predicted <= 0 || actual == null) return null;
    return actual - predicted;
  }

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _spin = CurvedAnimation(parent: _spinCtrl, curve: Curves.easeOutCubic);

    if (_hasBoard) {
      final probs = widget.outcome!.probabilities!;
      _cells = RewardConfig.boardCells(probs);
      _targetRotation = _computeTargetRotation(
        widget.outcome!.landedCategory ?? RouletteCategory.miss,
      );
      _spinCtrl.addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            mounted &&
            _phase == _RoulettePhase.spinning) {
          setState(() => _phase = _RoulettePhase.revealed);
        }
      });
      _spinStartTimer = Timer(const Duration(milliseconds: 700), _beginSpin);
    } else {
      _cells = const [];
      _phase = _RoulettePhase.revealed;
    }

    final before = widget.cumulativeTaskCountBefore;
    final after = widget.cumulativeTaskCountAfter;
    if (before != null && after != null) {
      final progressBefore = RewardConfig.progressFor(before);
      final progressAfter = RewardConfig.progressFor(after);
      _leveledUp = progressAfter.level > progressBefore.level;
      _leveledUpLevel = progressAfter.level;
      _leveledUpTitle = progressAfter.title;
    } else {
      _leveledUp = false;
      _leveledUpLevel = null;
      _leveledUpTitle = null;
    }

    if (_leveledUp) {
      _levelBurstTimer = Timer(const Duration(milliseconds: 4500), () {
        if (!mounted) return;
        setState(() => _showLevelBurst = true);
        _levelBurstHideTimer = Timer(const Duration(milliseconds: 2500), () {
          if (!mounted) return;
          setState(() => _showLevelBurst = false);
        });
      });
    }
  }

  /// 着地させたい区分のマス中心が上部ポインタの真下に来る回転角を求める。
  double _computeTargetRotation(RouletteCategory landed) {
    var start = 0.0;
    var midpoint = 0.0;
    for (final cell in _cells) {
      final sweep = cell.sweepFraction * 2 * math.pi;
      if (cell.category == landed) {
        midpoint = start + sweep / 2;
        break;
      }
      start += sweep;
    }
    const fullTurns = 4;
    return fullTurns * 2 * math.pi - midpoint;
  }

  void _skip() {
    if (_phase != _RoulettePhase.spinning) return;
    _spinCtrl.stop();
    _spinCtrl.value = 1.0;
    setState(() => _phase = _RoulettePhase.revealed);
  }

  void _beginSpin() {
    if (!mounted || _phase != _RoulettePhase.waiting) return;
    setState(() => _phase = _RoulettePhase.spinning);
    _spinCtrl.forward(from: 0);
  }

  @override
  void dispose() {
    _spinStartTimer?.cancel();
    _levelBurstTimer?.cancel();
    _levelBurstHideTimer?.cancel();
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('タスク完了')),
      body: Stack(
        children: [
          MessageGuard(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Icon(Icons.celebration, size: 56, color: scheme.primary),
                  const SizedBox(height: 8),
                  Text(
                    'おめでとう！',
                    textAlign: TextAlign.center,
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '「${widget.taskTitle}」を完了しました',
                    textAlign: TextAlign.center,
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  // お金は先に・確実に見せる（努力がゼロに見えないように）。
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: widget.rewardYen.toDouble()),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => Text(
                      '獲得金額：¥${_formatYen(value.round())}',
                      textAlign: TextAlign.center,
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.reward(context),
                      ),
                    ),
                  ),
                  if (widget.balanceBeforeYen != null &&
                      widget.balanceAfterYen != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatBalanceFlow(
                        widget.balanceBeforeYen!,
                        widget.balanceAfterYen!,
                      ),
                      textAlign: TextAlign.center,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                  if (_thisTaskErrorPercent != null) ...[
                    const SizedBox(height: 4),
                    // 分を主役に表示（確定仕様14）。
                    Text(
                      '今回の予測：${_thisTaskDiffMinutes! >= 0 ? '+' : ''}$_thisTaskDiffMinutes分'
                      '（${_thisTaskErrorPercent! >= 0 ? '+' : ''}$_thisTaskErrorPercent%）'
                      '　予測${widget.predictedMinutes}分→実績${widget.actualMinutes}分',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          if (_hasBoard) _buildRoulette(text),
                          _buildLevelSection(text, scheme),
                        ],
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('ホームに戻る'),
                  ),
                ],
              ),
            ),
          ),
          if (_showLevelBurst)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: RewardBurst(
                    assetName: 'level_up',
                    size: 240,
                    fallback: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.rewardContainer(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'レベルアップ！ Lv.$_leveledUpLevel',
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: AppColors.onRewardContainer(context),
                            ),
                          ),
                          Text(
                            '称号「$_leveledUpTitle」',
                            style: text.bodyMedium?.copyWith(
                              color: AppColors.onRewardContainer(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRoulette(TextTheme text) {
    final isSpinning = _phase == _RoulettePhase.spinning;
    return Column(
      children: [
        const SizedBox(height: 8),
        GestureDetector(
          onTap: isSpinning ? _skip : null,
          child: AnimatedBuilder(
            animation: _spin,
            builder: (context, _) => RouletteBoard(
              cells: _cells,
              rotation: _spin.value * _targetRotation,
              size: 220,
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: switch (_phase) {
            _RoulettePhase.waiting => Text(
              'ご褒美ルーレットを抽選します',
              key: const ValueKey('waiting'),
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            _RoulettePhase.spinning => Column(
              key: const ValueKey('spinning'),
              children: [
                Text(
                  '抽選中...',
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'タップでスキップ',
                  textAlign: TextAlign.center,
                  style: text.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
            _RoulettePhase.revealed => _buildResultMessage(text),
          },
        ),
        const SizedBox(height: 8),
        Text(
          'ご褒美の内容、出現確率はメニュー画面から変更できます',
          textAlign: TextAlign.center,
          style: text.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildResultMessage(TextTheme text) {
    final outcome = widget.outcome!;
    final scheme = Theme.of(context).colorScheme;
    String title;
    String? subtitle;
    Color color = scheme.primary;

    switch (outcome.kind) {
      case RouletteOutcomeKind.win:
        if (outcome.isInstantPermission) {
          title = '${outcome.tier!.label}！';
          subtitle = '今すぐ「${outcome.rewardName}」していい';
          color = RouletteBoard.colorFor(outcome.tier!, scheme);
        } else {
          title = '${outcome.tier!.label}！';
          subtitle = '「${outcome.rewardName}」のチケットをGET（在庫に追加）';
          color = RouletteBoard.colorFor(outcome.tier!, scheme);
        }
        break;
      case RouletteOutcomeKind.nearMiss:
        title = 'ハズレ';
        subtitle = '今回はご褒美なし。¥${_formatYen(widget.rewardYen)}は獲得済みです';
        color = scheme.onSurfaceVariant;
        break;
      case RouletteOutcomeKind.needsSetup:
        title = '${outcome.landedCategory?.label ?? '当たり'}！';
        subtitle = 'ご褒美が未設定です。メニューから登録しよう';
        color = scheme.onSurfaceVariant;
        break;
      case RouletteOutcomeKind.invalidConfig:
        title = '';
        subtitle = null;
        break;
    }

    return Column(
      key: const ValueKey('result'),
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: text.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, textAlign: TextAlign.center, style: text.titleSmall),
        ],
      ],
    );
  }

  Widget _buildLevelSection(TextTheme text, ColorScheme scheme) {
    final before = widget.cumulativeTaskCountBefore;
    final after = widget.cumulativeTaskCountAfter;
    if (before == null || after == null) return const SizedBox.shrink();

    final progressBefore = RewardConfig.progressFor(before);
    final progressAfter = RewardConfig.progressFor(after);
    final leveledUp = progressAfter.level > progressBefore.level;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          if (leveledUp) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.rewardContainer(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'レベルアップ！ Lv.${progressAfter.level}',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppColors.onRewardContainer(context),
                    ),
                  ),
                  Text(
                    '称号「${progressAfter.title}」',
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.onRewardContainer(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            'Lv.${progressAfter.level}　次のレベルまであと${progressAfter.remainingToNext}タスク',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progressAfter.fraction,
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  String _formatYen(int n) {
    return n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  /// 全角￥・全角数字で所持金の流れを表示する。
  String _formatBalanceFlow(int before, int after) {
    const digits = '０１２３４５６７８９';
    String fullWidth(int n) {
      final isNegative = n < 0;
      final absStr = n.abs().toString();
      final body = absStr.split('').map((c) => digits[int.parse(c)]).join();
      return isNegative ? '−$body' : body;
    }

    return '￥${fullWidth(before)}→${fullWidth(after)}';
  }
}

enum _RoulettePhase { waiting, spinning, revealed }
