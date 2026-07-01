import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
    switch (getPlatform(context)) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        // Only vertical scrollables get the iOS scrollbar. Horizontal pagers
        // (image carousels, onboarding) show no indicator, matching native iOS.
        if (details.direction == AxisDirection.up ||
            details.direction == AxisDirection.down) {
          return CupertinoScrollbar(
            controller: details.controller,
            child: child,
          );
        }
        return super.buildScrollbar(context, child, details);
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return super.buildScrollbar(context, child, details);
    }
  }
}
