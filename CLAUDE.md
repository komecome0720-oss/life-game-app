# CLAUDE.md — タスク管理アプリ（時間単価ご褒美システム）

> このプロジェクトに関する仕様・設計・実装状況・開発経過などのドキュメントは
> **すべて `obsidian/` 配下の Obsidian vault** に集約されている。
> 詳細を確認したり追記するときは、まず `obsidian/` を見ること。
>
> 実体は Google Drive 上：
> `~/Library/CloudStorage/GoogleDrive-n.kometani@re-startlaw.com/マイドライブ/Obsidian Vault - life_game_app`
> プロジェクト直下の `obsidian/` はそのシンボリックリンク（gitignore 済み）。

---

## 最低限おさえる情報

- 何を作るか：時間単価（月のお小遣い ÷ 月の目標時間）でタスクをこなすたびに仮想報酬が貯まるタスク管理アプリ
- スタック：Flutter / Firebase（Firestore + Auth）/ Riverpod + MVVM / iOS優先
- ファイル構成：feature-first（`lib/features/<feature>/{model,data,viewmodel,view,widgets}`）
- 状態管理：**Riverpod のみ**（Provider / GetX は禁止）

詳しくは → `obsidian/10_Project/プロジェクト概要.md` 起点で各ノートを辿る。

---

## 絶対に守ること（毎回参照）

### セキュリティ
- Firebase の API キーや秘密鍵をコードに直書きしない
  - `lib/firebase_options.dart`、`**/google-services.json`、`**/GoogleService-Info.plist` はコミット禁止＆Obsidianにも置かない
- Firestore のセキュリティルールは必ず設定（認証済みユーザーが自分のデータのみアクセス可）

### UIメッセージ（必読）
SnackBar / バナー等の非モーダル通知の表示中は、メッセージ以外のタップは「メッセージを閉じる」のみ。
- 新規 SnackBar は `lib/utils/app_messenger.dart` の `showAppSnackBar()` 経由でのみ表示
- 新規画面の `Scaffold.body` は `MessageGuard`（`lib/widgets/message_guard.dart`）でラップ
- 独自オーバーレイ通知も `messageVisibleNotifier` を ON/OFF して `MessageGuard` の対象にする

詳細 → `obsidian/10_Project/UI共通ルール.md`

---

## 開発の記録（必須運用）

**このプロジェクトで作業したら、必ず `obsidian/20_Daily/YYYY-MM-DD.md` に作業内容を追記すること。**

- ファイルがなければ新規作成（テンプレ：下記）
- セッション終了時にまとめて追記でよい
- 「何をやったか」「次にやること」「気づき・メモ」の3点を簡潔に
- 大きなマイルストーン（機能追加・大幅リファクタ等）は `obsidian/10_Project/開発経過.md` にも追記
- コミット作成時もこのログを更新する

### Daily テンプレート

```markdown
# YYYY-MM-DD

## 今日やったこと

-

## 次にやること

-

## メモ

-
```
