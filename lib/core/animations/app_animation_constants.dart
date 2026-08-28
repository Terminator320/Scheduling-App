import 'package:flutter/material.dart';

abstract final class AppAnimationDurations {
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration switcher = Duration(milliseconds: 220);
  static const Duration banner = Duration(milliseconds: 280);
  static const Duration tap = Duration(milliseconds: 90);
}

abstract final class AppAnimationCurves {
  static const Curve entrance = Curves.easeOutCubic;
  static const Curve tap = Curves.easeInOut;
}
