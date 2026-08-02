import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/deep_links/deep_link_dispatcher.dart';
import 'package:scheduling/core/logging/app_logger.dart';

void main() {
  late List<String> openedAppointments;
  late List<String> pushedCodes;
  late int noticeCount;
  late int loginWaitCount;
  var signedIn = false;
  var loginRouteReached = true;
  Future<void> Function(String)? openAppointmentOverride;

  DeepLinkDispatcher buildDispatcher() => DeepLinkDispatcher(
    logger: AppLogger(),
    isSignedIn: () => signedIn,
    openAppointment: (id) async {
      final override = openAppointmentOverride;
      if (override != null) return override(id);
      openedAppointments.add(id);
    },
    noticeSignOutToAcceptInvite: () async => noticeCount++,
    awaitLoginRoute: () async {
      loginWaitCount++;
      return loginRouteReached;
    },
    pushInviteCode: pushedCodes.add,
  );

  setUp(() {
    openedAppointments = [];
    pushedCodes = [];
    noticeCount = 0;
    loginWaitCount = 0;
    signedIn = false;
    loginRouteReached = true;
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
      await buildDispatcher().handleLink(
        Uri.parse('esproschedule://appointment?id=job-1&homeWidget'),
      );

      expect(openedAppointments, isEmpty);
      expect(pushedCodes, isEmpty);
    },
  );

  test('an invite link on a signed-out app pushes the code screen', () async {
    await buildDispatcher().handleLink(
      Uri.parse('esproschedule://invite?code=ABCD-EFGH-JKMN'),
    );

    expect(pushedCodes, ['ABCD-EFGH-JKMN']);
    expect(noticeCount, 0);
  });

  test('an invite link waits for the login route before pushing', () async {
    await buildDispatcher().handleLink(
      Uri.parse('esproschedule://invite?code=ABC'),
    );

    expect(loginWaitCount, 1);
  });

  test(
    'an invite link gives up silently when the login route never comes',
    () async {
      loginRouteReached = false;

      await buildDispatcher().handleLink(
        Uri.parse('esproschedule://invite?code=ABC'),
      );

      expect(pushedCodes, isEmpty);
      expect(noticeCount, 0);
    },
  );

  test(
    'an invite link on a live session only notices — it never signs out',
    () async {
      signedIn = true;

      await buildDispatcher().handleLink(
        Uri.parse('esproschedule://invite?code=ABC'),
      );

      expect(noticeCount, 1);
      expect(pushedCodes, isEmpty);
      expect(loginWaitCount, 0);
    },
  );

  test('an unknown host does nothing at all', () async {
    await buildDispatcher().handleLink(Uri.parse('esproschedule://settings'));

    expect(openedAppointments, isEmpty);
    expect(pushedCodes, isEmpty);
    expect(noticeCount, 0);
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
