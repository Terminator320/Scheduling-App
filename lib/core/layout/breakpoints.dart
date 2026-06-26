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

  /// Narrow-phone width gate: below this, dense rows stack vertically.
  static const double compactWidth = 360;

  /// Large-text gate: above this text scale, dense rows stack as if narrow.
  static const double compactTextScale = 1.4;

  /// Short-viewport height gate (e.g. landscape phones): sheets grow taller.
  static const double shortViewportHeight = 700;
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

  /// Dense rows (cards, headers, action bars) stack vertically: a narrow phone
  /// OR a large text scale that would otherwise overflow a horizontal row.
  bool get isCompact =>
      MediaQuery.sizeOf(this).width < Breakpoints.compactWidth ||
      MediaQuery.textScalerOf(this).scale(1) > Breakpoints.compactTextScale;

  /// Narrow phone by width alone (ignores text scale) — for layouts that only
  /// need to fold when the screen itself is narrow.
  bool get isNarrowWidth =>
      MediaQuery.sizeOf(this).width < Breakpoints.compactWidth;
}
