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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < Breakpoints.tablet) {
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
      },
    );
  }
}
