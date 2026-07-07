# 音源素材ライセンス一覧

すべて**商用利用可・クレジット（帰属）表示不要**のライセンス（CC0 1.0 または Pixabay Content License）。
App Store 配信の iOS アプリへの同梱に問題なし。ダウンロード日はいずれも 2026-07-06（bgm_waves_soothing.mp3のみ2026-07-07）。

| ファイル名 | 内容 | 入手元URL（ファイルページ） | 作者 | ライセンス | ダウンロード日 |
|---|---|---|---|---|---|
| bgm_waves_soothing.mp3 | 海岸の穏やかな波の音（Soothing Ocean Waves、132.1秒） | https://pixabay.com/sound-effects/soothing-ocean-waves-372489/ | DRAGON-STUDIO | Pixabay Content License（商用利用可・クレジット表示不要、再配布・単体販売は不可） | 2026-07-07 |
| bgm_river.m4a | 川のせせらぎ（渓流の接写録音、68.9秒） | https://commons.wikimedia.org/wiki/File:433589_jackthemurray_stream-river-water-up-close.wav | jackthemurray | CC0 1.0 | 2026-07-06 |
| bgm_fire.m4a | 焚き火・暖炉の炎のパチパチ音（ループ用、29.3秒） | https://opengameart.org/content/fireplace-sound-loop | PagDev | CC0 1.0 | 2026-07-06 |
| bgm_birds.m4a | 鳥のさえずり（公園の環境音、448.9秒 ≒ 7分29秒） | https://opengameart.org/content/park-ambiences （収録ファイル "park_ambience_birds.wav"） | Thimras | CC0 1.0 | 2026-07-06 |
| sfx_drum.wav | 太鼓（フレームドラム）の一打、2.5秒 | https://commons.wikimedia.org/wiki/File:B%C4%99ben_obr%C4%99czowy_uderzenia_pojedyncze.flac | Swietliste | CC0 1.0 | 2026-07-06 |
| sfx_bell.wav | ベル・チャイムの単発音（0.62秒） | https://opengameart.org/content/pleasing-bell-sound-effect | Spring Spring | CC0 1.0 | 2026-07-06 |
| sfx_trumpet.mp3 | トランペットのファンファーレ（2.5秒） | https://opengameart.org/content/trumpet-fanfare （収録ファイル "castlefanfare.mp3"） | gchoc | CC0 1.0 | 2026-07-06 |

## 加工メモ（CC0 のため改変自由）

- **bgm_river.m4a** — 元は WAV（19.8MB, 48kHz/24bit）。`afconvert` で AAC 128kbps の m4a に変換。
- **bgm_fire.m4a** — 元は WAV（10.3MB）。`afconvert` で AAC 128kbps の m4a に変換。
- **bgm_birds.m4a** — 元は WAV（86.2MB）。`afconvert` で AAC 80kbps の m4a に変換（5MB以下目標のため）。
- **sfx_drum.wav** — 元は FLAC（9.2秒・複数打）。最初の一打（0.45秒〜2.95秒）を ffmpeg で切り出し、末尾0.3秒フェードアウト、16bit WAV 化。
- sfx_bell.wav / sfx_trumpet.mp3 は元ファイルのまま（無加工）。
- **bgm_waves_soothing.mp3** — 旧素材（"R23-46-Beach Waves"）に意図しない人の声が混入していたため差し替え。一度 "R25-03-Four Big Ocean Waves"（CC0）にしたが波が激しめだったため、より穏やかな Pixabay 素材 "Soothing Ocean Waves" にユーザーが自ら選定し差し替え。無加工。

## ライセンス確認方法

- Wikimedia Commons：各ファイルページの機械可読メタデータ（LicenseShortName = CC0）を API で確認。
- OpenGameArt：各コンテンツページのライセンス表記（CC0 バッジ）を確認。
- Internet Archive：アイテムメタデータの licenseurl（creativecommons.org/publicdomain/zero/1.0/）を確認。
- Pixabay：各コンテンツページの「Pixabay Content License」表記（商用利用可・帰属表示不要・再配布不可）を確認。
