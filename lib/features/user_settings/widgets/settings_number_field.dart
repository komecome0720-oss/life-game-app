import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 設定画面用の数字のみ `TextFormField`（suffix 付き）。
class SettingsNumberField extends StatelessWidget {
  const SettingsNumberField({
    super.key,
    required this.controller,
    required this.label,
    required this.suffix,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    );
  }
}
