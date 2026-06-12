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
