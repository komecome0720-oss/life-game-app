import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/prediction_chip_sheet.dart';

/// 予測宣言チップシートに表示するプリセット時間（分）を編集するダイアログ。
/// 削除は最低1個残す。追加は 1〜1440 分にクランプ・重複排除・昇順ソートして保存。
class PredictionChipSettingsDialog extends ConsumerStatefulWidget {
  const PredictionChipSettingsDialog({super.key});

  @override
  ConsumerState<PredictionChipSettingsDialog> createState() =>
      _PredictionChipSettingsDialogState();
}

class _PredictionChipSettingsDialogState
    extends ConsumerState<PredictionChipSettingsDialog> {
  late List<int> _minutes;
  final _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _minutes = List.of(
      ref.read(userSettingsProvider).settings.predictionChipMinutes,
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _remove(int m) {
    if (_minutes.length <= 1) return;
    setState(() => _minutes.remove(m));
  }

  void _add() {
    final v = int.tryParse(_inputController.text);
    if (v == null) return;
    final clamped = v.clamp(1, 1440);
    setState(() {
      if (!_minutes.contains(clamped)) {
        _minutes = ({..._minutes, clamped}.toList()..sort());
      }
      _inputController.clear();
    });
  }

  Future<void> _save() async {
    final sorted = ({..._minutes}.toList()..sort());
    final ok = await ref
        .read(userSettingsProvider.notifier)
        .savePreferences(predictionChipMinutes: sorted);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      showAppSnackBar(context, const SnackBar(content: Text('保存に失敗しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('予測チップの時間'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _minutes)
                  Chip(
                    label: Text(formatPredictionMinutes(m)),
                    onDeleted: _minutes.length > 1 ? () => _remove(m) : null,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '追加（分）',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
