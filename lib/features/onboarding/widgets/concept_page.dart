import 'package:flutter/material.dart';

/// オンボーディング①：アプリのコンセプトを1ページで伝える説明画面（純粋ウィジェット）。
///
/// 伝える内容は3点：
/// 1. タスクをこなして健康な生活を送るとお金が貯まる
/// 2. 溜まったお金で現実世界の欲しいものを買える
/// 3. もらえるお金は月に使える金額から計算している
class ConceptPage extends StatelessWidget {
  const ConceptPage({super.key, required this.onStart, required this.buttonLabel});

  final VoidCallback onStart;

  /// 初回フローでは「はじめる」、再閲覧では「画面の説明を見る」など呼び出し側で切り替える。
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            const Spacer(),
            Icon(
              Icons.auto_awesome,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '人生のゲーム化をはじめよう',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _ConceptPoint(
              icon: Icons.task_alt,
              color: theme.colorScheme.primary,
              text: 'タスクをこなして健康な生活を送ると、お金が貯まっていくよ',
            ),
            const SizedBox(height: 24),
            _ConceptPoint(
              icon: Icons.favorite,
              color: Colors.pink,
              text: '溜まったお金で現実世界の欲しいものを買おう',
            ),
            const SizedBox(height: 24),
            _ConceptPoint(
              icon: Icons.calculate,
              color: Colors.blue,
              text: 'もらえるお金は月に使える金額から計算しているよ',
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onStart,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(buttonLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConceptPoint extends StatelessWidget {
  const _ConceptPoint({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}
