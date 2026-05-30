import 'package:flutter/material.dart';

class AppAnimationDurations {
  const AppAnimationDurations._();

  static const Duration quick = Duration(milliseconds: 180);
  static const Duration switcher = Duration(milliseconds: 220);
  static const Duration banner = Duration(milliseconds: 280);
  static const Duration tap = Duration(milliseconds: 90);
}

class AppAnimationCurves {
  const AppAnimationCurves._();

  static const Curve entrance = Curves.easeOutCubic;
  static const Curve tap = Curves.easeInOut;
}
