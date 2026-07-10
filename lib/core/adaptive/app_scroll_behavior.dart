import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';

/// App-wide scroll behavior: renders a fading iOS-style [CupertinoScrollbar] on
/// iOS/macOS, and defers to the Material default (no persistent scrollbar on
/// touch, standard overscroll glow) everywhere else — so Android is unchanged.
/// Set on `MaterialApp.scrollBehavior`.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Only vertical scrollables get the iOS scrollbar. Horizontal pagers
    // (image carousels, onboarding) show no indicator, matching native iOS.
    final isVertical =
        details.direction == AxisDirection.up ||
        details.direction == AxisDirection.down;
    if (context.isCupertino && isVertical) {
      return CupertinoScrollbar(controller: details.controller, child: child);
    }
    return super.buildScrollbar(context, child, details);
  }
}
