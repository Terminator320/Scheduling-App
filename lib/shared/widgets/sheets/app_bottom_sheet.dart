import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

/// Opens a modal bottom sheet with this app's standard chrome —
/// scroll-controlled, transparent barrier background (the sheet content
/// supplies its own surface), and the shared [AppMotion.sheetStyle]
/// open/close animation. [shape] is optional — only the calendar add/detail
/// sheets round the top corners explicitly; other sheets rely on their own
/// content chrome (e.g. `DraggableSheetFrame`) for that.
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
