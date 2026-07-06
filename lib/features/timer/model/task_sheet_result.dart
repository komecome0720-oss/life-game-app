/// タスク詳細シート（カレンダー予定・ToDo共通）を閉じるときの結果。
///
/// シート自身はタイマー開始処理（promote・Firestore書き込み・ロック画面push）を
/// 行わず、「スタートが押されたので閉じる」ことだけを呼び出し元へ伝える。
/// 呼び出し元は安定した context で `TimerLockLauncher.openForStart` /
/// `openForPomodoro` を呼ぶ（シートのpopがロック画面を誤って閉じる問題や
/// unmounted context を避けるため）。
enum TaskSheetResult {
  /// スタートボタンが押された。呼び出し元は通常タイマーのロック画面を起動する。
  startTimer,

  /// ポモドーロボタンが押された。呼び出し元はポモドーロのロック画面を起動する。
  startPomodoro,
}
