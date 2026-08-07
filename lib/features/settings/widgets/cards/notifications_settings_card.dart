import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/notifications/push_notification_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/live_activity/application/live_activity_preference.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/settings/widgets/cards/settings_tiles.dart';
import 'package:scheduling/l10n/l10n.dart';

/// OS-notification and Live Activity rows. Watches the auth/support/enabled
/// providers; the host supplies the tap + toggle handlers.
class NotificationsSettingsCard extends ConsumerWidget {
  const NotificationsSettingsCard({
    required this.onNotificationsTap,
    required this.onToggleLiveActivity,
    super.key,
  });

  final void Function(AuthorizationStatus status) onNotificationsTap;
  final void Function({required bool value}) onToggleLiveActivity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Default to notDetermined so the row offers enable rather than a misleading "On".
    final status =
        ref.watch(notificationAuthStatusProvider).asData?.value ??
        AuthorizationStatus.notDetermined;
    final granted = PushNotificationService.isGranted(status);
    // Hidden when the device/OS version can't host a Live Activity card.
    final showLiveActivity =
        ref.watch(liveActivitySupportedProvider).asData?.value ?? false;
    return SettingsSectionCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsTile(
            iconBg: granted ? scheme.primaryContainer : scheme.errorContainer,
            icon: granted
                ? Icons.notifications_active_rounded
                : Icons.notifications_off_rounded,
            iconColor: granted ? scheme.primary : scheme.error,
            label: context.l10n.settings_notifications,
            isLast: !showLiveActivity,
            trailing: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sp4,
              runSpacing: AppSpacing.sp4,
              children: [
                SettingsTrailingPill(
                  label: granted
                      ? context.l10n.settings_notificationsOn
                      : context.l10n.settings_notificationsOff,
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            onTap: () => onNotificationsTap(status),
          ),
          if (showLiveActivity) ...[
            const SettingsTileDivider(),
            SettingsTile(
              iconBg: scheme.primaryContainer,
              icon: Icons.directions_car_rounded,
              iconColor: scheme.primary,
              label: context.l10n.settings_liveActivity,
              isLast: true,
              trailing: Switch.adaptive(
                value: ref.watch(liveActivityEnabledProvider),
                onChanged: (value) => onToggleLiveActivity(value: value),
                activeTrackColor: scheme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
