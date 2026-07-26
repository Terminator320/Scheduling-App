import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';

/// App-wide scroll behavior (set on `MaterialApp.scrollBehavior`): a fading
/// iOS-style [CupertinoScrollbar] on iOS/macOS, Material default elsewhere
/// (Android unchanged).
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Only vertical scrollables get the iOS scrollbar; horizontal pagers show none, matching native iOS.
    final isVertical =
        details.direction == AxisDirection.up ||
        details.direction == AxisDirection.down;
    if (context.isCupertino && isVertical) {
      return CupertinoScrollbar(controller: details.controller, child: child);
    }
    return super.buildScrollbar(context, child, details);
  }
}
