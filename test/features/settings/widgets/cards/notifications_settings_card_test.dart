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
import 'package:scheduling/l10n/l10n.dart';

Widget _harness({
  required Future<void> liveActivityReady,
  bool liveActivityEnabled = true,
  bool isTogglingLiveActivity = false,
  bool? travelAlertsEnabled,
  bool isTogglingTravelAlerts = false,
  void Function({required bool value})? onToggleLiveActivity,
  void Function({required bool value})? onToggleTravelAlerts,
}) {
  return ProviderScope(
    overrides: [
      notificationAuthStatusProvider.overrideWith(
        (ref) async => AuthorizationStatus.authorized,
      ),
      liveActivitySupportedProvider.overrideWith((ref) async => true),
      liveActivityPreferenceReadyProvider.overrideWith((ref) => liveActivityReady),
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
          onToggleLiveActivity:
              onToggleLiveActivity ?? ({required value}) {},
          isTogglingLiveActivity: isTogglingLiveActivity,
          travelAlertsEnabled: travelAlertsEnabled,
          onToggleTravelAlerts:
              onToggleTravelAlerts ?? ({required value}) {},
          isTogglingTravelAlerts: isTogglingTravelAlerts,
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

    expect(find.text('Live Activity'), findsNothing);

    completer.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('Live Activity'), findsOneWidget);
  });

  testWidgets('disables the Live Activity switch while its write is in flight', (
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
  });

  testWidgets('disables the travel-alerts switch while its write is in flight', (
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
  });
}
