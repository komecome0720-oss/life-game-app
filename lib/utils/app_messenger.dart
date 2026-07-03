import 'package:flutter/material.dart';

/// 非モーダルメッセージ（SnackBar 等）が画面上に表示中かどうかを通知する。
/// `MessageGuard` がこの値を監視してタップバリアの表示を切り替える。
final ValueNotifier<bool> messageVisibleNotifier = ValueNotifier<bool>(false);

int _currentToken = 0;

/// アプリ全体で利用する SnackBar 表示ヘルパー。
/// 直接 `ScaffoldMessenger.of(context).showSnackBar(...)` を呼ばずに必ずこれを使うこと。
///
/// [blocking] を `false` にすると、表示中も裏の画面の操作をブロックしない
/// （保存成功など、ユーザーの注意を引き留める必要のない通知向け）。
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showAppSnackBar(
  BuildContext context,
  SnackBar snackBar, {
  bool blocking = true,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return null;
  messenger.hideCurrentSnackBar();
  final myToken = ++_currentToken;
  messageVisibleNotifier.value = blocking;
  final controller = messenger.showSnackBar(snackBar);
  controller.closed.then((_) {
    if (myToken == _currentToken && blocking) {
      messageVisibleNotifier.value = false;
    }
  });
  return controller;
}

void dismissAppSnackBar(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
}
