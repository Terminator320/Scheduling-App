import 'package:flutter/material.dart';
import 'package:scheduling/features/settings/widgets/views/text_size_view.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/app_back_button.dart';

class TextSizeScreen extends StatelessWidget {
  const TextSizeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        leading: AppBackButton(onTap: () => Navigator.pop(context)),
        title: Text(
          context.l10n.settings_textSize,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: TextSizeView(onApplied: () => Navigator.pop(context)),
    );
  }
}
