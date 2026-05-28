import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:task_manager/features/wish_list/viewmodel/wish_list_viewmodel.dart';
import 'package:task_manager/utils/app_messenger.dart';

class AddWishItemSheet extends ConsumerStatefulWidget {
  const AddWishItemSheet({super.key});

  @override
  ConsumerState<AddWishItemSheet> createState() => _AddWishItemSheetState();
}

class _AddWishItemSheetState extends ConsumerState<AddWishItemSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _shopUrlCtrl = TextEditingController();
  File? _selectedImage;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _shopUrlCtrl.dispose();
    super.dispose();
  }

  void _showImagePickerSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('カメラで撮影'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('アルバムから選ぶ'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 80);
    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      String imageUrl = '';
      if (_selectedImage != null) {
        final url = await ref
            .read(wishListProvider.notifier)
            .uploadWishImage(_selectedImage!);
        imageUrl = url ?? '';
      }

      await ref.read(wishListProvider.notifier).addItem(
            name: _nameCtrl.text.trim(),
            price: int.parse(_priceCtrl.text),
            shopUrl: _shopUrlCtrl.text.trim(),
            imageUrl: imageUrl,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          const SnackBar(content: Text('画像のアップロードに失敗しました')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('欲しいものを追加', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: '商品名 *', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? '商品名を入力してください' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '価格 *', suffixText: '円', border: OutlineInputBorder()),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n <= 0) return '価格を入力してください';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _shopUrlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'ショップURL（任意）', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _isSaving ? null : _showImagePickerSheet,
              child: _selectedImage != null
                  ? Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _selectedImage!,
                            height: 120,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedImage = null),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(Icons.close, size: 18, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.outline,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo, color: colorScheme.onSurfaceVariant),
                          const SizedBox(height: 4),
                          Text(
                            '画像を追加（任意）',
                            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isSaving ? null : _submit,
              child: _isSaving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('追加'),
            ),
          ],
        ),
      ),
    );
  }
}
