import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/deep_links/deep_link_dispatcher.dart';
import 'package:scheduling/core/logging/app_logger.dart';

void main() {
  late List<String> openedAppointments;
  Future<void> Function(String)? openAppointmentOverride;

  DeepLinkDispatcher buildDispatcher() => DeepLinkDispatcher(
    logger: AppLogger(),
    openAppointment: (id) async {
      final override = openAppointmentOverride;
      if (override != null) return await override(id);
      openedAppointments.add(id);
    },
  );

  setUp(() {
    openedAppointments = [];
    openAppointmentOverride = null;
  });

  test('an appointment link opens the appointment', () async {
    await buildDispatcher().handleLink(
      Uri.parse('esproschedule://appointment?id=job-1'),
    );

    expect(openedAppointments, ['job-1']);
  });

  test(
    'a homeWidget link opens nothing — the channel already owns it',
    () async {
      // Both plugins observe the same openURL, so handling it here too would
      // open the appointment sheet twice per widget/Live-Activity/Siri tap.
      await buildDispatcher().handleLink(
        Uri.parse('esproschedule://appointment?id=job-1&homeWidget'),
      );

      expect(openedAppointments, isEmpty);
    },
  );

  test('an invite link does nothing — the code flow is retired', () async {
    // Old links can still be in someone's messages. They must fall through
    // rather than reach a screen that no longer exists.
    await buildDispatcher().handleLink(
      Uri.parse('esproschedule://invite?code=ABCD-EFGH-JKMN'),
    );

    expect(openedAppointments, isEmpty);
  });

  test('an unknown host does nothing at all', () async {
    await buildDispatcher().handleLink(Uri.parse('esproschedule://settings'));

    expect(openedAppointments, isEmpty);
  });

  test(
    'a throwing handler is swallowed instead of escaping the zone',
    () async {
      openAppointmentOverride = (_) async => throw StateError('boom');

      await expectLater(
        buildDispatcher().handleLink(
          Uri.parse('esproschedule://appointment?id=job-1'),
        ),
        completes,
      );
    },
  );
}
