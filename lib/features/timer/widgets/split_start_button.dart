import 'package:flutter/material.dart';

/// 大型一体型スタートボタンの高さ。両シート（カレンダー予定・ToDo）で共通。
const double kSplitStartButtonHeight = 112;

/// ウィジェットテスト用の安定したキー群。
const Key kSplitStartButtonStartKey = Key('split_start_button_start');
const Key kSplitStartButtonPomodoroKey = Key('split_start_button_pomodoro');
const Key kSplitStartButtonSettingsKey = Key('split_start_button_settings');

/// 左右二分割のスタートボタン。
///
/// 左＝▶︎アイコンのみ（従来の通常タイマー開始）、
/// 右＝トマト＋▶︎アイコン（ポモドーロ開始）、どちらも文字なし。
/// 右ボタンの右上には歯車アイコンを Stack で重ね、タップでポモドーロ設定画面へ
/// 遷移する（トマトボタン本体のタップとは独立したヒット領域を持つ）。
///
/// `lib/widgets/task_event_detail_sheet.dart` と
/// `lib/features/todo/widgets/todo_task_detail_sheet.dart` の両方から使う
/// 共通ウィジェット（意図的な重複構造を持つ両シートの唯一の共有部品）。
class SplitStartButton extends StatelessWidget {
  const SplitStartButton({
    super.key,
    required this.onTapStart,
    required this.onTapPomodoro,
    required this.onTapSettings,
  });

  /// 左ボタン：従来の通常タイマー開始。
  final VoidCallback onTapStart;

  /// 右ボタン：ポモドーロ開始。
  final VoidCallback onTapPomodoro;

  /// 右ボタン右上の歯車：ポモドーロ設定画面へ遷移。
  final VoidCallback onTapSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: kSplitStartButtonHeight,
      child: Row(
        children: [
          Expanded(
            child: _StartHalf(
              key: kSplitStartButtonStartKey,
              onTap: onTapStart,
              backgroundColor: scheme.secondaryContainer,
              foregroundColor: scheme.onSecondaryContainer,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(20),
                right: Radius.circular(4),
              ),
              child: const Icon(Icons.play_arrow_rounded, size: 32),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _StartHalf(
                  key: kSplitStartButtonPomodoroKey,
                  onTap: onTapPomodoro,
                  backgroundColor: scheme.tertiaryContainer,
                  foregroundColor: scheme.onTertiaryContainer,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(4),
                    right: Radius.circular(20),
                  ),
                  child: const _TomatoPlayIcon(),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: _SettingsGearButton(
                    key: kSplitStartButtonSettingsKey,
                    onTap: onTapSettings,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StartHalf extends StatelessWidget {
  const _StartHalf({
    super.key,
    required this.onTap,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderRadius,
    required this.child,
  });

  final VoidCallback onTap;
  final Color backgroundColor;
  final Color foregroundColor;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: kSplitStartButtonHeight,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
        ),
        child: child,
      ),
    );
  }
}

/// トマトのフリー素材画像（Twemoji 🍅、CC-BY 4.0 →
/// `assets/images/LICENSES.md` 参照）の上に、左ボタンと同サイズの
/// 再生アイコンを重ねる。
class _TomatoPlayIcon extends StatelessWidget {
  const _TomatoPlayIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/tomato_twemoji.png',
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            // トマトの実の中心（ヘタの分だけ画像中央より下）に合わせる。
            top: 14,
            child: Icon(
              Icons.play_arrow_rounded,
              size: 32,
              color: Colors.white,
              shadows: [
                Shadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ポモドーロボタン右上に重ねる歯車。ボタン本体のタップと干渉しないよう
/// 独立した GestureDetector で十分なヒット領域（>=32px）を確保する。
class _SettingsGearButton extends StatelessWidget {
  const _SettingsGearButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(Icons.settings, size: 18, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
