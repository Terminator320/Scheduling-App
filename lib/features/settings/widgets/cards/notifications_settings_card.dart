import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/notifications/push_notification_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/live_activity/application/live_activity_preference.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/settings/widgets/cards/settings_tiles.dart';
import 'package:scheduling/l10n/l10n.dart';

/// OS-notification and Live Activity rows.
class NotificationsSettingsCard extends ConsumerWidget {
  const NotificationsSettingsCard({
    required this.onNotificationsTap,
    required this.liveActivityEnabled,
    required this.onToggleLiveActivity,
    required this.travelAlertsEnabled,
    required this.onToggleTravelAlerts,
    required this.locationSharingEnabled,
    required this.onLocationSharingTap,
    required this.onToggleLocationSharing,
    this.isTogglingLiveActivity = false,
    this.isTogglingTravelAlerts = false,
    this.isTogglingLocationSharing = false,
    this.tourWrap,
    super.key,
  });

  final void Function(AuthorizationStatus status) onNotificationsTap;
  final bool liveActivityEnabled;
  final void Function({required bool value}) onToggleLiveActivity;
  final bool isTogglingLiveActivity;

  /// Null while the person's own record is still loading, which hides the row
  /// rather than rendering a switch in a state that may be wrong.
  final bool? travelAlertsEnabled;
  final void Function({required bool value}) onToggleTravelAlerts;
  final bool isTogglingTravelAlerts;
  final bool? locationSharingEnabled;
  final VoidCallback onLocationSharingTap;
  final void Function({required bool value}) onToggleLocationSharing;
  final bool isTogglingLocationSharing;

  /// Lets the Settings tour wrap a row as its own step. Null off-tour, so the
  /// card stays usable untoured. Keyed by step id rather than named per row,
  /// so a second toured row here costs a call, not a parameter.
  final Widget Function(TourStepId, Widget)? tourWrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Default to notDetermined so the row offers enable rather than a misleading "On".
    final status =
        ref.watch(notificationAuthStatusProvider).asData?.value ??
        AuthorizationStatus.notDetermined;
    final granted = PushNotificationService.isGranted(status);
    final liveActivityReady = ref
        .watch(liveActivityPreferenceReadyProvider)
        .hasValue;
    // Hidden when the device/OS version can't host a Live Activity card.
    final showLiveActivity =
        (ref.watch(liveActivitySupportedProvider).asData?.value ?? false) &&
        liveActivityReady;
    final showTravelAlerts = travelAlertsEnabled != null;
    final showLocationSharing = locationSharingEnabled != null;
    // Held as a local so the tour's wrap can be applied to it by name.
    final locationTile = showLocationSharing
        ? SettingsTile(
            iconBg: scheme.primaryContainer,
            icon: Icons.location_on_rounded,
            iconColor: scheme.primary,
            label: context.l10n.settings_locationSharing,
            isLast: true,
            onTap: onLocationSharingTap,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch.adaptive(
                  key: const Key('locationSharingSwitch'),
                  value: locationSharingEnabled!,
                  onChanged: isTogglingLocationSharing
                      ? null
                      : (value) => onToggleLocationSharing(value: value),
                  activeTrackColor: scheme.primary,
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          )
        : null;
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
            isLast:
                !showLiveActivity && !showTravelAlerts && !showLocationSharing,
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
              isLast: !showTravelAlerts && !showLocationSharing,
              onTap: isTogglingLiveActivity
                  ? null
                  : () => onToggleLiveActivity(value: !liveActivityEnabled),
              trailing: Switch.adaptive(
                value: liveActivityEnabled,
                onChanged: isTogglingLiveActivity
                    ? null
                    : (value) => onToggleLiveActivity(value: value),
                activeTrackColor: scheme.primary,
              ),
            ),
          ],
          if (showTravelAlerts) ...[
            const SettingsTileDivider(),
            SettingsTile(
              iconBg: scheme.primaryContainer,
              icon: Icons.schedule_send_rounded,
              iconColor: scheme.primary,
              label: context.l10n.settings_travelAlerts,
              isLast: !showLocationSharing,
              onTap: isTogglingTravelAlerts
                  ? null
                  : () => onToggleTravelAlerts(value: !travelAlertsEnabled!),
              trailing: Switch.adaptive(
                key: const Key('travelAlertsSwitch'),
                value: travelAlertsEnabled!,
                onChanged: isTogglingTravelAlerts
                    ? null
                    : (value) => onToggleTravelAlerts(value: value),
                activeTrackColor: scheme.primary,
              ),
            ),
          ],
          if (locationTile != null) ...[
            const SettingsTileDivider(),
            tourWrap?.call(
                  TourStepId.settingsLocationSharing,
                  locationTile,
                ) ??
                locationTile,
          ],
        ],
      ),
    );
  }
}
