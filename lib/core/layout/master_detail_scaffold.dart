import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/breakpoints.dart';

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
        return Row(
          children: [
            Expanded(flex: masterFlex, child: master),
            divider,
            Expanded(flex: detailFlex, child: detail ?? placeholder),
          ],
        );
      },
    );
  }
}
