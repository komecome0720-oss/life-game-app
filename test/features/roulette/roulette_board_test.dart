import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/roulette/model/reward_config.dart';
import 'package:task_manager/features/roulette/widgets/roulette_board.dart';

void main() {
  test('roulette board colors are fixed per category', () {
    final scheme = ThemeData.light().colorScheme;

    expect(
      RouletteBoard.colorFor(RouletteCategory.jackpot, scheme),
      const Color(0xFFE53935),
    );
    expect(
      RouletteBoard.colorFor(RouletteCategory.chu, scheme),
      const Color(0xFFF0A72B),
    );
    expect(
      RouletteBoard.colorFor(RouletteCategory.sho, scheme),
      const Color(0xFF1E88E5),
    );
    expect(
      RouletteBoard.colorFor(RouletteCategory.miss, scheme),
      const Color(0xFFA7B0BC),
    );
  });
}
