import 'package:flutter/material.dart';

import 'package:scheduling/features/settings/widgets/cards/settings_tiles.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Biometric app-lock row. The host supplies the current value and owns the
/// toggle handler (it checks biometric availability and surfaces notices).
class SecuritySettingsCard extends StatelessWidget {
  const SecuritySettingsCard({
    required this.enabled,
    required this.onToggleAppLock,
    this.isBusy = false,
    super.key,
  });

  final bool enabled;
  final bool isBusy;

  /// `Future`-returning on purpose.
  final Future<void> Function({required bool value}) onToggleAppLock;

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      child: SettingsSwitchTile(
        icon: Icons.fingerprint_rounded,
        label: context.l10n.settings_appLock,
        value: enabled,
        isBusy: isBusy,
        onChanged: onToggleAppLock,
      ),
    );
  }
}
