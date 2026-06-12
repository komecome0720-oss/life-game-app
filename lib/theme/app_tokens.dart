import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

abstract final class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static BorderRadius get card => BorderRadius.circular(md);
  static BorderRadius get chip => BorderRadius.circular(sm);
}

/// 収支±色。ダークモードでコントラストを確保するため shade を切り替える。
abstract final class AppColors {
  static Color positive(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.green.shade300
          : Colors.green.shade700;

  static Color negative(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.deepOrange.shade300
          : Colors.deepOrange.shade700;
}
