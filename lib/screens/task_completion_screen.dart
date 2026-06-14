import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:task_manager/features/roulette/model/reward_config.dart';
import 'package:task_manager/features/roulette/model/roulette_outcome.dart';
import 'package:task_manager/features/roulette/widgets/roulette_board.dart';
import 'package:task_manager/widgets/message_guard.dart';

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

  @override
  State<TaskCompletionScreen> createState() => _TaskCompletionScreenState();
}

class _TaskCompletionScreenState extends State<TaskCompletionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinCtrl;
  late final Animation<double> _spin;
  late final List<RouletteCell> _cells;
  double _targetRotation = 0;
  bool _revealed = false;

  bool get _hasBoard => widget.outcome?.probabilities != null;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _spin = CurvedAnimation(parent: _spinCtrl, curve: Curves.easeOutCubic);

    if (_hasBoard) {
      final probs = widget.outcome!.probabilities!;
      _cells = RewardConfig.boardCells(probs);
      _targetRotation = _computeTargetRotation(
        widget.outcome!.landedCategory ?? RouletteCategory.miss,
      );
      _spinCtrl.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _revealed = true);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _spinCtrl.forward();
      });
    } else {
      _cells = const [];
      _revealed = true;
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
    if (_revealed) return;
    _spinCtrl.stop();
    _spinCtrl.value = 1.0;
    setState(() => _revealed = true);
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('タスク完了')),
      body: MessageGuard(
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
                style:
                    text.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                '「${widget.taskTitle}」を完了しました',
                textAlign: TextAlign.center,
                style: text.titleSmall,
              ),
              const SizedBox(height: 12),
              // お金は先に・確実に見せる（努力がゼロに見えないように）。
              Text(
                '獲得金額：¥${_formatYen(widget.rewardYen)}',
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800, color: scheme.primary),
              ),
              if (widget.balanceBeforeYen != null &&
                  widget.balanceAfterYen != null) ...[
                const SizedBox(height: 4),
                Text(
                  _formatBalanceFlow(
                      widget.balanceBeforeYen!, widget.balanceAfterYen!),
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700, color: scheme.primary),
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
    );
  }

  Widget _buildRoulette(TextTheme text) {
    return Column(
      children: [
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _skip,
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
          child: _revealed
              ? _buildResultMessage(text)
              : Text(
                  'タップでスキップ',
                  key: const ValueKey('spinning'),
                  style: text.bodySmall,
                ),
        ),
        const SizedBox(height: 8),
        Text(
          'ご褒美の内容、出現確率はメニュー画面から変更できます',
          textAlign: TextAlign.center,
          style: text.labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
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
        title = 'もう少し！';
        subtitle = 'お金はしっかり獲得しています';
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
              fontWeight: FontWeight.w900, color: color),
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
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'レベルアップ！ Lv.${progressAfter.level}',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    '称号「${progressAfter.title}」',
                    style: text.bodyMedium
                        ?.copyWith(color: scheme.onPrimaryContainer),
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
