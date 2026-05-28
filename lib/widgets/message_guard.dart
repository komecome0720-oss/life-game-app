import 'package:flutter/material.dart';
import 'package:task_manager/utils/app_messenger.dart';

/// `Scaffold.body` をラップする透過バリア。
///
/// 非モーダルメッセージ（SnackBar 等）が表示されている間、
/// 子ウィジェット上のタップをすべて消化し、
/// 「メッセージを閉じる」だけの動作に置き換える。
///
/// SnackBar 自体は Scaffold が body の上に別スロットで描画するため、
/// このバリアでは覆われず、`SnackBarAction` ボタンは通常通り押せる。
class MessageGuard extends StatelessWidget {
  final Widget child;
  const MessageGuard({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: messageVisibleNotifier,
      builder: (ctx, visible, _) {
        return Stack(
          children: [
            Positioned.fill(child: child),
            if (visible)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    ScaffoldMessenger.maybeOf(ctx)?.hideCurrentSnackBar();
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
