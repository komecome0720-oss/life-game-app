import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

const _presetAvatars = [
  (icon: Icons.person, color: Colors.blue),
  (icon: Icons.face, color: Colors.green),
  (icon: Icons.sentiment_satisfied_alt, color: Colors.orange),
  (icon: Icons.self_improvement, color: Colors.purple),
  (icon: Icons.emoji_emotions, color: Colors.pink),
  (icon: Icons.sports_martial_arts, color: Colors.teal),
  (icon: Icons.star, color: Colors.amber),
];

class ProfileImagePicker extends StatelessWidget {
  const ProfileImagePicker({
    super.key,
    required this.avatarUrl,
    required this.onFileSelected,
    required this.onPresetSelected,
  });

  final String avatarUrl;
  final void Function(File file) onFileSelected;
  final void Function(int presetIndex) onPresetSelected;

  void _showSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('カメラで撮影'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pick(context, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('カメラロールから選ぶ'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pick(context, ImageSource.gallery);
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'プリセットアバター',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _presetAvatars.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final p = _presetAvatars[i];
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      onPresetSelected(i);
                    },
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: p.color.withValues(alpha: 0.2),
                      child: Icon(p.icon, color: p.color, size: 28),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 80);
    if (picked != null) onFileSelected(File(picked.path));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showSheet(context),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundImage: avatarUrl.isNotEmpty
                ? NetworkImage(avatarUrl)
                : null,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: avatarUrl.isEmpty
                ? Icon(
                    Icons.person,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: CircleAvatar(
              radius: 13,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.edit, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

IconData presetAvatarIcon(int index) => _presetAvatars[index].icon;
Color presetAvatarColor(int index) => _presetAvatars[index].color;
