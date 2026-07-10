#!/usr/bin/env bash
set -euo pipefail

# TestFlight (Internal Testing) 向けのビルドを固定化するスクリプト
# アップロード自体は Xcode Organizer または Transporter で実行する

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter コマンドが見つかりません。Flutter SDKをインストールしてください。"
  exit 1
fi

flutter clean
flutter pub get
flutter build ipa --release

# --- Xcode Organizer に登録 ---------------------------------------------------
# flutter build ipa はアーカイブを build/ios/archive/ にしか作らないため、
# Xcode の Organizer（Window > Organizer）には出てこない。
# Organizer は ~/Library/Developer/Xcode/Archives/<日付>/ 配下の .xcarchive を
# 表示するので、ビルドしたアーカイブをそこへコピーして登録する。
ARCHIVE_SRC="build/ios/archive/Runner.xcarchive"
if [ -d "$ARCHIVE_SRC" ]; then
  ORG_DIR="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
  mkdir -p "$ORG_DIR"
  DEST="$ORG_DIR/Runner $(date '+%Y-%m-%d %H.%M').xcarchive"
  cp -R "$ARCHIVE_SRC" "$DEST"
  echo "Xcode Organizer に登録しました: $DEST"
else
  echo "警告: $ARCHIVE_SRC が見つからず、Organizer への登録をスキップしました。"
fi
# -----------------------------------------------------------------------------

echo ""
echo "IPAビルドが完了しました。"
echo "出力先: build/ios/ipa/"
echo "アップロードは次のいずれかで実行してください:"
echo "  - Xcode > Window > Organizer > Archives から該当ビルドを選び Distribute App"
echo "  - もしくは build/ios/ipa/*.ipa を Transporter にドラッグ"
