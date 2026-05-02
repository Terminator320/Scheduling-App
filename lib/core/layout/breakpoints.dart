import 'package:flutter/widgets.dart';

class Breakpoints {
  Breakpoints._();

  /// Two-pane (master-detail + nav rail) threshold. Set at the Material 3
  /// "expanded" width so phone-portrait and tablet-portrait stay single
  /// column; only genuinely large screens (landscape, large tablets) split.
  static const double tablet = 840;

  /// Extended (labelled) nav-rail threshold — only on large screens, so the
  /// rail doesn't expand the moment two-pane appears.
  static const double expanded = 1200;
}

extension ResponsiveContext on BuildContext {
  bool get isWide => MediaQuery.sizeOf(this).width >= Breakpoints.tablet;

  bool get isExpanded => MediaQuery.sizeOf(this).width >= Breakpoints.expanded;

  double get screenWidth => MediaQuery.sizeOf(this).width;
}
