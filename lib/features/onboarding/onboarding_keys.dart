import 'package:flutter/material.dart';

/// コーチマークがくり抜き対象とするウィジェットに付与する GlobalKey 一覧。
///
/// home_screen.dart / main.dart から参照され、CoachMarkOverlay の各ステップが
/// これらの key の RenderBox を元にくり抜き矩形と吹き出し位置を決める。
abstract final class OnboardingKeys {
  static final userStatusPanel = GlobalKey(debugLabel: 'onb_userStatusPanel');
  static final healthPanel = GlobalKey(debugLabel: 'onb_healthPanel');
  static final weekSchedule = GlobalKey(debugLabel: 'onb_weekSchedule');
  static final addTaskFab = GlobalKey(debugLabel: 'onb_addTaskFab');
  static final todoTab = GlobalKey(debugLabel: 'onb_todoTab');
  static final wishTab = GlobalKey(debugLabel: 'onb_wishTab');
  static final menuButton = GlobalKey(debugLabel: 'onb_menuButton');
}
