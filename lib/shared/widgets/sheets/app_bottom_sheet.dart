import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

/// Opens a modal bottom sheet with the app's standard chrome — scroll-controlled,
/// transparent barrier, shared [AppMotion.sheetStyle] animation. [shape] is
/// optional: only calendar add/detail sheets round the top corners explicitly,
/// everything else relies on its own content chrome.
Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  ShapeBorder? shape,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    sheetAnimationStyle: AppMotion.sheetStyle,
    shape: shape,
    builder: builder,
  );
}
