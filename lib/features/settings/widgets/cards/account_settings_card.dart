import 'package:flutter/material.dart';

import 'package:scheduling/features/settings/widgets/cards/settings_tiles.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Sign-out and delete-account rows. Both actions live in the host state
/// (they mutate its busy flags), so this card takes them as callbacks.
class AccountSettingsCard extends StatelessWidget {
  const AccountSettingsCard({
    required this.onSignOut,
    required this.onDeleteAccount,
    this.isBusy = false,
    super.key,
  });

  final VoidCallback onSignOut;
  final VoidCallback onDeleteAccount;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsSectionCard(
      child: Column(
        children: [
          SettingsTile(
            iconBg: scheme.errorContainer,
            icon: Icons.logout_rounded,
            iconColor: scheme.error,
            label: context.l10n.settings_logOut,
            labelColor: scheme.error,
            onTap: isBusy ? null : onSignOut,
          ),
          const SettingsTileDivider(),
          SettingsTile(
            iconBg: scheme.errorContainer,
            icon: Icons.delete_forever_rounded,
            iconColor: scheme.error,
            label: context.l10n.settings_deleteAccount,
            labelColor: scheme.error,
            isLast: true,
            onTap: isBusy ? null : onDeleteAccount,
          ),
        ],
      ),
    );
  }
}
