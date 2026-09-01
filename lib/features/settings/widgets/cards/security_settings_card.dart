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

  /// `Future`-returning on purpose. Typed `void Function` this silently
  /// DROPPED the host's future, so a keychain fault while writing the flag
  /// escaped to the zone handler as a FATAL Crashlytics record and the switch
  /// snapped back with no message at all.
  final Future<void> Function({required bool value}) onToggleAppLock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsSectionCard(
      child: SettingsTile(
        iconBg: scheme.primaryContainer,
        icon: Icons.fingerprint_rounded,
        iconColor: scheme.primary,
        label: context.l10n.settings_appLock,
        isLast: true,
        // The whole row toggles. Without it only the switch is tappable, and a
        // shrink-wrapped Switch.adaptive is about 31pt — under both minimums,
        // on the row whose label is the thing you are aiming at.
        onTap: isBusy ? null : () => onToggleAppLock(value: !enabled),
        trailing: Switch.adaptive(
          value: enabled,
          onChanged: isBusy ? null : (value) => onToggleAppLock(value: value),
          activeTrackColor: scheme.primary,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
