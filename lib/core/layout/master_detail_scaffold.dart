import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/primary_scroll_scope.dart';

class MasterDetailScaffold extends StatelessWidget {
  const MasterDetailScaffold({
    required this.master, required this.placeholder, super.key,
    this.detail,
    this.masterFlex = 4,
    this.detailFlex = 6,
    this.divider = const VerticalDivider(width: 1, thickness: 1),
  });

  final Widget master;
  final Widget? detail;
  final Widget placeholder;
  final int masterFlex;
  final int detailFlex;
  final Widget divider;

  @override
  Widget build(BuildContext context) {
    // Single column on phones (both orientations) — a landscape phone gets the
    // nav rail but is too narrow for a readable detail pane, so the screen
    // shows the list here and opens the detail as a pushed sheet instead. Only
    // tablet-class devices show the two panes. This must match the tap-time
    // gate the screens use (`context.isTwoPane`) or a selection lands in a pane
    // that isn't rendered.
    if (!context.isTwoPane) {
      return master;
    }
    // Master and detail are shown side by side, so their scrollables are
    // alive at once. Scope each pane under its own PrimaryScrollController
    // so both primary lists don't attach to the same one (a Scrollbar
    // requires a single ScrollPosition per controller).
    return Row(
      children: [
        Expanded(
          flex: masterFlex,
          child: PrimaryScrollScope(child: master),
        ),
        divider,
        Expanded(
          flex: detailFlex,
          child: PrimaryScrollScope(child: detail ?? placeholder),
        ),
      ],
    );
  }
}
