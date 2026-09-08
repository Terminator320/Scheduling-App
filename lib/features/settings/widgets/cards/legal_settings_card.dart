import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/constants/app_urls.dart';
import 'package:scheduling/core/launchers/web_url_launcher.dart';
import 'package:scheduling/features/settings/widgets/cards/settings_tiles.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Privacy-policy and terms rows — self-contained (each opens its hosted URL
/// via the shared launcher).
///
/// The terms row is the DURABLE route to the agreement. The setup screen's
/// consent checkbox also links to it, but that screen is shown once, only to a
/// new employee, and never again — so without this row anyone who accepted the
/// terms had no way back to them.
class LegalSettingsCard extends ConsumerWidget {
  const LegalSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final openIcon = Icon(
      Icons.open_in_new_rounded,
      size: 18,
      color: scheme.onSurfaceVariant,
    );
    return SettingsSectionCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsTile(
            iconBg: scheme.secondaryContainer,
            icon: Icons.privacy_tip_rounded,
            iconColor: scheme.secondary,
            label: context.l10n.settings_privacyPolicy,
            trailing: openIcon,
            onTap: () => launchWebUrl(context, ref, AppUrls.privacyPolicy),
          ),
          SettingsTile(
            iconBg: scheme.secondaryContainer,
            icon: Icons.description_rounded,
            iconColor: scheme.secondary,
            label: context.l10n.settings_termsOfService,
            trailing: openIcon,
            onTap: () => launchWebUrl(context, ref, AppUrls.termsOfService),
          ),
        ],
      ),
    );
  }
}
