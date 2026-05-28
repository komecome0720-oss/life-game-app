import 'package:flutter/material.dart';

/// 非モーダルメッセージ（SnackBar 等）が画面上に表示中かどうかを通知する。
/// `MessageGuard` がこの値を監視してタップバリアの表示を切り替える。
final ValueNotifier<bool> messageVisibleNotifier = ValueNotifier<bool>(false);

int _currentToken = 0;

/// アプリ全体で利用する SnackBar 表示ヘルパー。
/// 直接 `ScaffoldMessenger.of(context).showSnackBar(...)` を呼ばずに必ずこれを使うこと。
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showAppSnackBar(
  BuildContext context,
  SnackBar snackBar,
) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return null;
  messenger.hideCurrentSnackBar();
  final myToken = ++_currentToken;
  messageVisibleNotifier.value = true;
  final controller = messenger.showSnackBar(snackBar);
  controller.closed.then((_) {
    if (myToken == _currentToken) {
      messageVisibleNotifier.value = false;
    }
  });
  return controller;
}

void dismissAppSnackBar(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
}
