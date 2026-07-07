import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/utils/health_goal.dart';

void main() {
  group('healthTotalColor', () {
    const cases = {
      0: Colors.grey,
      1: Colors.blue,
      29: Colors.blue,
      30: Colors.green,
      59: Colors.green,
      60: Colors.amber,
      79: Colors.amber,
      80: Colors.red,
      100: Colors.red,
    };

    for (final entry in cases.entries) {
      test('score ${entry.key} (light) is ${entry.value}', () {
        final color = healthTotalColor(entry.key, Brightness.light);
        expect(color, isA<Color>());
        expect(_hueName(color), entry.value);
      });

      test('score ${entry.key} (dark) is ${entry.value}', () {
        final color = healthTotalColor(entry.key, Brightness.dark);
        expect(color, isA<Color>());
        expect(_hueName(color), entry.value);
      });
    }

    test('light and dark shades differ', () {
      for (final score in cases.keys) {
        final light = healthTotalColor(score, Brightness.light);
        final dark = healthTotalColor(score, Brightness.dark);
        expect(light, isNot(equals(dark)), reason: 'score=$score');
      }
    });
  });
}

/// 期待する色系統(grey/blue/green/amber/red)ごとの代表色と比較するため、
/// shadeを問わず系統だけを判定するヘルパー
MaterialColor _hueName(Color color) {
  const candidates = <MaterialColor>[
    Colors.grey,
    Colors.blue,
    Colors.green,
    Colors.amber,
    Colors.red,
  ];
  for (final hue in candidates) {
    for (final shade in [
      hue.shade300,
      hue.shade400,
      hue.shade500,
      hue.shade600,
      hue.shade700,
    ]) {
      if (shade.toARGB32() == color.toARGB32()) return hue;
    }
  }
  throw StateError('Unknown hue for $color');
}
