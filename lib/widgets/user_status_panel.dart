import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';
import 'package:task_manager/features/user_settings/view/user_settings_screen.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';

class UserStatusPanel extends ConsumerWidget {
  const UserStatusPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uState = ref.watch(userSettingsProvider);
    final settings = uState.settings;
    final isFirstLoad = uState.isLoading && _isDefault(settings);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isFirstLoad
            ? null
            : () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                      builder: (_) => const UserSettingsScreen()),
                ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ステータス',
                  style: text.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 6),
              if (isFirstLoad)
                ...List.generate(
                  4,
                  (_) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: scheme.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                _line(Icons.badge_outlined, '名前',
                    settings.displayName.isEmpty ? '—' : settings.displayName, text),
                _line(Icons.trending_up, 'レベル', '${settings.level}', text),
                _line(Icons.savings_outlined, '所持金',
                    '¥${_fmt(settings.totalEarned)}', text),
                _line(
                    Icons.schedule,
                    '時間単価',
                    settings.hourlyRate > 0
                        ? '¥${_fmt(settings.hourlyRate.round())}/h'
                        : '—',
                    text),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _isDefault(UserSettings s) {
    return s.displayName.isEmpty &&
        s.level == 1 &&
        s.totalEarned == 0 &&
        s.monthlyBudget == 0;
  }

  Widget _line(IconData icon, String label, String value, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Expanded(
            flex: 4,
            child: Text(label, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 6,
            child: Text(value, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  String _fmt(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
}
