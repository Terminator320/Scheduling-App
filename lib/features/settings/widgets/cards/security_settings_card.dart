import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/settings/application/app_lock_provider.dart';
import 'package:scheduling/features/settings/widgets/cards/settings_tiles.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Biometric app-lock row. Watches the lock preference; the host owns the
/// toggle handler (it checks biometric availability and surfaces notices).
class SecuritySettingsCard extends ConsumerWidget {
  const SecuritySettingsCard({required this.onToggleAppLock, super.key});

  final void Function({required bool value}) onToggleAppLock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsSectionCard(
      child: SettingsTile(
        iconBg: scheme.primaryContainer,
        icon: Icons.fingerprint_rounded,
        iconColor: scheme.primary,
        label: context.l10n.settings_appLock,
        isLast: true,
        trailing: Switch.adaptive(
          value: ref.watch(appLockEnabledProvider),
          onChanged: (value) => onToggleAppLock(value: value),
          activeTrackColor: scheme.primary,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
