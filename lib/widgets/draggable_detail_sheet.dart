import 'package:flutter/material.dart';

/// 詳細シート共通のモーダルボトムシート表示。
///
/// 中身が画面高を超えるとスクロールがドラッグを食ってスワイプで閉じられなく
/// なるため、DraggableScrollableSheet でスクロールとシートドラッグを連動させる
/// （スクロール最上部からの下スワイプでシートごと閉じる）。
///
/// - 最小サイズまで引き下げられたら maybePop する。強制 pop ではなく maybePop
///   なので、中身の PopScope（未保存ガード等）が正しく効く。
/// - [builder] に渡される ScrollController を中身のスクロールビューへ必ず接続すること。
Future<T?> showDraggableDetailSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, ScrollController scrollController)
      builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      var popRequested = false;
      return Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: NotificationListener<DraggableScrollableNotification>(
          onNotification: (notification) {
            if (!popRequested &&
                notification.extent <= notification.minExtent + 0.005) {
              popRequested = true;
              Navigator.of(sheetContext).maybePop().then((popped) {
                if (!popped) popRequested = false;
              });
            }
            return false;
          },
          child: DraggableScrollableSheet(
            expand: false,
            snap: true,
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            // 組み込みの閉じ処理は強制 pop で PopScope（未保存ガード）を素通り
            // してしまうため無効化し、上の maybePop 経由に一本化する。
            shouldCloseOnMinExtent: false,
            builder: builder,
          ),
        ),
      );
    },
  );
}
