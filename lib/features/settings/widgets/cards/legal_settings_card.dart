import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/constants/app_urls.dart';
import 'package:scheduling/core/launchers/web_url_launcher.dart';
import 'package:scheduling/features/settings/widgets/cards/settings_tiles.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Privacy-policy row — self-contained (opens the policy URL via the shared
/// launcher).
class LegalSettingsCard extends ConsumerWidget {
  const LegalSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsSectionCard(
      child: SettingsTile(
        iconBg: scheme.secondaryContainer,
        icon: Icons.privacy_tip_rounded,
        iconColor: scheme.secondary,
        label: context.l10n.settings_privacyPolicy,
        isLast: true,
        trailing: Icon(
          Icons.open_in_new_rounded,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        onTap: () => launchWebUrl(context, ref, AppUrls.privacyPolicy),
      ),
    );
  }
}
