import 'package:flutter/material.dart';
import 'package:task_manager/theme/app_tokens.dart';
import 'package:task_manager/widgets/message_guard.dart';
import 'package:task_manager/widgets/reward_burst.dart';

class WishItemCompletionScreen extends StatelessWidget {
  const WishItemCompletionScreen({
    super.key,
    required this.userName,
    required this.itemPrice,
    required this.balanceBeforeYen,
    required this.balanceAfterYen,
  });

  final String userName;
  final int itemPrice;
  final int balanceBeforeYen;
  final int balanceAfterYen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('アイテム獲得')),
      body: MessageGuard(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              IgnorePointer(
                child: RewardBurst(
                  assetName: 'gift',
                  size: 160,
                  fallback: Icon(Icons.celebration,
                      size: 72, color: AppColors.reward(context)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'おめでとう、$userNameは\n${_formatMoney(itemPrice)}円をゲットした！',
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _formatBalanceFlow(balanceBeforeYen, balanceAfterYen),
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.reward(context),
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('戻る'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMoney(int n) {
    return n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  String _formatBalanceFlow(int before, int after) {
    return '所持金：${_formatMoney(before)}円→${_formatMoney(after)}円';
  }
}
