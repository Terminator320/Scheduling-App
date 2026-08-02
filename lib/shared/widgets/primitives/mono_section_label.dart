import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

/// Mono all-caps section header inside a form sheet — the appointment form's
/// own, promoted out of the private copies the client and person sheets each
/// grew. Pass the text already uppercase, like `SectionLabel`.
class MonoSectionLabel extends StatelessWidget {
  const MonoSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).monoType.label);
}
