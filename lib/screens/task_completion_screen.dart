import 'package:flutter/material.dart';
import 'package:task_manager/widgets/message_guard.dart';

class TaskCompletionScreen extends StatelessWidget {
  const TaskCompletionScreen({
    super.key,
    required this.taskTitle,
    required this.rewardYen,
    this.balanceBeforeYen,
    this.balanceAfterYen,
  });

  final String taskTitle;
  final int rewardYen;

  /// 所持金の変化を表示するときのみ指定（例: ￥２０５４０→２０５９０）。
  final int? balanceBeforeYen;
  final int? balanceAfterYen;

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
            const SizedBox(height: 24),
            Icon(Icons.celebration, size: 72, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'おめでとう！',
              textAlign: TextAlign.center,
              style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              '「$taskTitle」を完了しました',
              textAlign: TextAlign.center,
              style: text.titleMedium,
            ),
            const SizedBox(height: 24),
            Text(
              '獲得金額：¥${_formatYen(rewardYen)}',
              textAlign: TextAlign.center,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary),
            ),
            if (balanceBeforeYen != null && balanceAfterYen != null) ...[
              const SizedBox(height: 8),
              Text(
                _formatBalanceFlow(balanceBeforeYen!, balanceAfterYen!),
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary),
              ),
            ],
            const Spacer(),
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
