import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/primary_scroll_scope.dart';

class MasterDetailScaffold extends StatelessWidget {
  const MasterDetailScaffold({
    required this.master,
    required this.placeholder,
    super.key,
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
    // Only tablet-class devices show two panes.
    if (!context.isTwoPane) {
      return master;
    }
    // Give each pane its own primary scroll controller.
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
