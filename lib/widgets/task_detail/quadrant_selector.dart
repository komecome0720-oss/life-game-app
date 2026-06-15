import 'package:flutter/material.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';

/// 2×2の象限セレクター。
/// 配置は To-Do マトリクス画面と同じ（左上=2黄, 右上=1赤, 左下=4灰, 右下=3水）。
class QuadrantSelector extends StatelessWidget {
  const QuadrantSelector({
    super.key,
    required this.selected,
    required this.onSelect,
    this.enabled = true,
  });

  final Quadrant selected;
  final ValueChanged<Quadrant> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // 配置順：todo_matrix_screen.dart:89-103 と同じハードコード
    //   上段: notUrgentImportant(2黄) | urgentImportant(1赤)
    //   下段: notUrgentNotImportant(4灰) | urgentNotImportant(3水)
    return Column(
      children: [
        Row(
          children: [
            _Cell(q: Quadrant.notUrgentImportant, selected: selected, onSelect: onSelect, enabled: enabled),
            const SizedBox(width: 8),
            _Cell(q: Quadrant.urgentImportant, selected: selected, onSelect: onSelect, enabled: enabled),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _Cell(q: Quadrant.notUrgentNotImportant, selected: selected, onSelect: onSelect, enabled: enabled),
            const SizedBox(width: 8),
            _Cell(q: Quadrant.urgentNotImportant, selected: selected, onSelect: onSelect, enabled: enabled),
          ],
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.q,
    required this.selected,
    required this.onSelect,
    required this.enabled,
  });

  final Quadrant q;
  final Quadrant selected;
  final ValueChanged<Quadrant> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isSelected = q == selected;
    final accent = q.accentColor(scheme);
    final bg = isSelected
        ? q.backgroundColor(scheme)
        : q.backgroundColor(scheme).withValues(alpha: 0.4);

    return Expanded(
      child: InkWell(
        onTap: enabled ? () => onSelect(q) : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: accent, width: 2)
                : Border.all(color: accent.withValues(alpha: 0.3), width: 1),
          ),
          // 数字＋説明を1行に（スペース節約）。説明は FittedBox で縮小し省略を避ける。
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${q.number}',
                style: text.labelLarge?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    q.adjectives,
                    maxLines: 1,
                    style: text.labelSmall?.copyWith(
                      color: isSelected
                          ? accent
                          : scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 4),
                Icon(Icons.check_circle, size: 14, color: accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
