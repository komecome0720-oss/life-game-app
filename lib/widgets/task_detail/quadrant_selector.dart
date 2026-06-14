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
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: accent, width: 2)
                : Border.all(color: accent.withValues(alpha: 0.3), width: 1),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
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
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    q.adjectives,
                    style: text.labelSmall?.copyWith(
                      color: isSelected
                          ? accent
                          : scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    maxLines: 2,
                    softWrap: true,
                  ),
                ],
              ),
              if (isSelected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(Icons.check_circle, size: 16, color: accent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
