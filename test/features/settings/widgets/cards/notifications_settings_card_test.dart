import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/live_activity/application/live_activity_preference.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/settings/widgets/cards/notifications_settings_card.dart';
import 'package:scheduling/features/settings/widgets/cards/settings_tiles.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _harness({
  required Future<void> liveActivityReady,
  bool liveActivityEnabled = true,
  bool isTogglingLiveActivity = false,
  bool? travelAlertsEnabled,
  bool isTogglingTravelAlerts = false,
  bool? locationSharingEnabled,
  bool isTogglingLocationSharing = false,
  void Function({required bool value})? onToggleLiveActivity,
  void Function({required bool value})? onToggleTravelAlerts,
  void Function({required bool value})? onToggleLocationSharing,
}) {
  return ProviderScope(
    overrides: [
      notificationAuthStatusProvider.overrideWith(
        (ref) async => AuthorizationStatus.authorized,
      ),
      liveActivitySupportedProvider.overrideWith((ref) async => true),
      liveActivityPreferenceReadyProvider.overrideWith(
        (ref) => liveActivityReady,
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: NotificationsSettingsCard(
          onNotificationsTap: (_) {},
          liveActivityEnabled: liveActivityEnabled,
          onToggleLiveActivity: onToggleLiveActivity ?? ({required value}) {},
          isTogglingLiveActivity: isTogglingLiveActivity,
          travelAlertsEnabled: travelAlertsEnabled,
          onToggleTravelAlerts: onToggleTravelAlerts ?? ({required value}) {},
          isTogglingTravelAlerts: isTogglingTravelAlerts,
          locationSharingEnabled: locationSharingEnabled,
          onLocationSharingTap: () {},
          onToggleLocationSharing:
              onToggleLocationSharing ?? ({required value}) {},
          isTogglingLocationSharing: isTogglingLocationSharing,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('hides the Live Activity row until the preference is loaded', (
    tester,
  ) async {
    final completer = Completer<void>();

    await tester.pumpWidget(_harness(liveActivityReady: completer.future));
    await tester.pump();

    expect(find.text('Live job card'), findsNothing);

    completer.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('Live job card'), findsOneWidget);
  });

  testWidgets(
    'disables the Live Activity switch while its write is in flight',
    (
      tester,
    ) async {
      var calls = 0;

      await tester.pumpWidget(
        _harness(
          liveActivityReady: Future<void>.value(),
          isTogglingLiveActivity: true,
          onToggleLiveActivity: ({required value}) => calls++,
        ),
      );
      await tester.pump();

      final toggle = tester.widget<Switch>(
        find.byType(Switch).first,
      );
      expect(toggle.onChanged, isNull);
      expect(calls, 0);
    },
  );

  testWidgets(
    'disables the travel-alerts switch while its write is in flight',
    (
      tester,
    ) async {
      var calls = 0;

      await tester.pumpWidget(
        _harness(
          liveActivityReady: Future<void>.value(),
          travelAlertsEnabled: true,
          isTogglingTravelAlerts: true,
          onToggleTravelAlerts: ({required value}) => calls++,
        ),
      );
      await tester.pump();

      final toggle = tester.widget<Switch>(
        find.byKey(const Key('travelAlertsSwitch')),
      );
      expect(toggle.onChanged, isNull);
      expect(calls, 0);
    },
  );

  testWidgets('shows and disables the location sharing switch independently', (
    tester,
  ) async {
    var calls = 0;

    await tester.pumpWidget(
      _harness(
        liveActivityReady: Future<void>.value(),
        locationSharingEnabled: true,
        isTogglingLocationSharing: true,
        onToggleLocationSharing: ({required value}) => calls++,
      ),
    );
    await tester.pump();

    expect(find.text('Staff map location'), findsOneWidget);
    final toggle = tester.widget<Switch>(
      find.byKey(const Key('locationSharingSwitch')),
    );
    expect(toggle.onChanged, isNull);
    expect(calls, 0);
  });

  testWidgets('every switch row is shrink-wrapped, so they render alike', (
    tester,
  ) async {
    // A padded Switch.adaptive is taller than a shrink-wrapped one, so a row
    // that spells its own switch renders at a different height from the rest
    // of the same Settings screen. Three of these four had already drifted.
    await tester.pumpWidget(
      _harness(
        liveActivityReady: Future<void>.value(),
        travelAlertsEnabled: true,
        locationSharingEnabled: true,
      ),
    );
    await tester.pump();

    final switches = tester.widgetList<Switch>(find.byType(Switch));
    expect(switches, hasLength(3));
    for (final toggle in switches) {
      expect(
        toggle.materialTapTargetSize,
        MaterialTapTargetSize.shrinkWrap,
        reason: 'a padded switch makes its row taller than its siblings',
      );
    }
  });

  testWidgets('divides the rows it actually rendered', (tester) async {
    // The dividers are indexed off the built list rather than each row
    // computing whether it is last, so a hidden row cannot leave a hanging
    // rule and a new row costs no edit to the rows above it.
    await tester.pumpWidget(
      _harness(
        liveActivityReady: Future<void>.value(),
        travelAlertsEnabled: true,
      ),
    );
    await tester.pump();

    expect(find.byType(SettingsTileDivider), findsNWidgets(2));
    expect(find.byType(SettingsTile), findsNWidgets(3));
  });
}
