import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/widgets/prediction_chip_settings_dialog.dart';

/// 宣言の正を解決する共通ヘルパー。[CalendarTask.predictionDeclared] が
/// true のときのみ estimatedMinutes を返す（未宣言なら null）。
/// 全タスク種別（ToDo・カレンダー予定）で共通して使う。
int? declaredPredictedMinutes(CalendarTask task) =>
    task.predictionDeclared ? (task.estimatedMinutes ?? 0) : null;

/// 分表示（時間+分）のフォーマット。
String formatPredictionMinutes(int m) {
  if (m < 60) return '$m分';
  if (m % 60 == 0) return '${m ~/ 60}時間';
  return '${m ~/ 60}時間${m % 60}分';
}

/// 予測宣言チップシート。タイマー／ポモドーロ開始時、空きスロットからの
/// 予定作成時に呼ぶ。チップをタップした瞬間に選択値を返して閉じる
/// （宣言＝スタート動作。参考情報（枠の長さ等）は表示しない）。
/// デフォルト選択は無く、[highlighted] は宣言済みタスクの現在値の
/// ハイライト表示にのみ使う。キャンセル時（バックドロップタップ等）は null。
Future<int?> showPredictionChipSheet(
  BuildContext context, {
  required WidgetRef ref,
  int? highlighted,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PredictionChipSheetContent(highlighted: highlighted),
  );
}

/// 自由入力（分）ダイアログ。決定で 1〜1440 にクランプした分を返し、
/// キャンセル時は null。TextEditingController のライフサイクルは
/// ダイアログ側（StatefulWidget）が管理する。
Future<int?> showPredictionFreeInputDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (_) => const _PredictionFreeInputDialog(),
  );
}

class _PredictionFreeInputDialog extends StatefulWidget {
  const _PredictionFreeInputDialog();

  @override
  State<_PredictionFreeInputDialog> createState() =>
      _PredictionFreeInputDialogState();
}

class _PredictionFreeInputDialogState
    extends State<_PredictionFreeInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_controller.text);
    if (v == null || v <= 0) return;
    Navigator.pop(context, v.clamp(1, 1440));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自由入力（分）'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(suffixText: '分'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(onPressed: _submit, child: const Text('決定')),
      ],
    );
  }
}

class _PredictionChipSheetContent extends ConsumerWidget {
  const _PredictionChipSheetContent({this.highlighted});

  final int? highlighted;

  Future<void> _openFreeInput(BuildContext context) async {
    final minutes = await showPredictionFreeInputDialog(context);
    if (minutes != null && context.mounted) {
      Navigator.pop(context, minutes);
    }
  }

  Future<void> _openSettings(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const PredictionChipSettingsDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final presets = ref.watch(
      userSettingsProvider.select((s) => s.settings.predictionChipMinutes),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '何分で終わらせる？',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _openSettings(context),
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'プリセットを編集',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in presets)
                  ChoiceChip(
                    label: Text(formatPredictionMinutes(m)),
                    selected: highlighted == m,
                    onSelected: (_) => Navigator.pop(context, m),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.edit, size: 18),
                  label: const Text('自由入力'),
                  onPressed: () => _openFreeInput(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
