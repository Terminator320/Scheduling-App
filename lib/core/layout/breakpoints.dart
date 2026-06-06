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

  /// Any device held in landscape (wider than tall).
  bool get isLandscape =>
      MediaQuery.orientationOf(this) == Orientation.landscape;

  /// Use the side nav rail + multi-pane treatment instead of the
  /// hamburger-drawer / bottom-sheet phone layout: genuinely wide screens
  /// (tablets, iPad) OR any device in landscape. Portrait phones stay
  /// single-column — this never lowers the [Breakpoints.tablet] width gate,
  /// it only adds the orientation path.
  bool get isSplitLayout => isWide || isLandscape;
}
