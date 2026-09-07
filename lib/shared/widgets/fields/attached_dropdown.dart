import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

/// The bordered suggestion list that attaches under a text field.
///
/// One owner of the chrome the address field and the client picker share — a
/// hand-written copy in each is how the same shape drifts on radius or border
/// colour, which is what `SheetPanel` already exists to stop.
class AttachedDropdown extends StatelessWidget {
  const AttachedDropdown({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: AppSpacing.sp4),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(AppRadius.r12),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
