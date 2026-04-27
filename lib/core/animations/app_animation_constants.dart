import 'package:flutter/material.dart';

// Shared duration tokens — change here to retime the whole app.
class AppAnimationDurations {
  const AppAnimationDurations._();

  static const Duration entrance = Duration(milliseconds: 820);
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

class AppStagger {
  const AppStagger._();

  // Each item plays for 52% of the total timeline; items overlap because
  // delay (8%) < itemDuration (52%), giving a cascading feel.
  static const double itemDuration = 0.52;
  static const double delay = 0.08;
}
