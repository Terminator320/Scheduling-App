import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/l10n/l10n.dart';

FirebaseException _fb(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  // We test classification through the public composeErrorNotice, since the
  // classifier itself is private to error_cause.dart.
  late String Function(Object error) noticeFor;

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            noticeFor = (error) =>
                composeErrorNotice(context, intro: 'Intro', error: error);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  String expected(String cause) => l10n.error_noticeWithCause('Intro', cause);

  group('error classification (via composeErrorNotice)', () {
    testWidgets('network-ish Firebase codes map to offline', (tester) async {
      await pumpHost(tester);
      expect(noticeFor(_fb('unavailable')), expected(l10n.error_causeOffline));
      expect(
        noticeFor(_fb('network-request-failed')),
        expected(l10n.error_causeOffline),
      );
      expect(
        noticeFor(_fb('deadline-exceeded')),
        expected(l10n.error_causeOffline),
      );
    });

    testWidgets('permission-denied maps to permissionDenied', (tester) async {
      await pumpHost(tester);
      expect(
        noticeFor(_fb('permission-denied')),
        expected(l10n.error_causePermissionDenied),
      );
    });

    testWidgets('not-found maps to notFound', (tester) async {
      await pumpHost(tester);
      expect(noticeFor(_fb('not-found')), expected(l10n.error_causeNotFound));
    });

    testWidgets('socket and timeout exceptions map to offline', (
      tester,
    ) async {
      await pumpHost(tester);
      expect(
        noticeFor(const SocketException('x')),
        expected(l10n.error_causeOffline),
      );
      expect(
        noticeFor(TimeoutException('x')),
        expected(l10n.error_causeOffline),
      );
    });

    testWidgets('unauthenticated maps to signedOut', (tester) async {
      await pumpHost(tester);
      expect(
        noticeFor(_fb('unauthenticated')),
        expected(l10n.error_causeSignedOut),
      );
    });

    testWidgets('rate-limit codes map to tooManyAttempts', (tester) async {
      await pumpHost(tester);
      expect(
        noticeFor(_fb('resource-exhausted')),
        expected(l10n.error_causeTooManyAttempts),
      );
      expect(
        noticeFor(_fb('too-many-requests')),
        expected(l10n.error_causeTooManyAttempts),
      );
    });

    testWidgets('rejected-payload codes map to invalidData', (tester) async {
      await pumpHost(tester);
      expect(
        noticeFor(_fb('invalid-argument')),
        expected(l10n.error_causeInvalidData),
      );
    });

    testWidgets('anything else maps to unknown', (tester) async {
      await pumpHost(tester);
      expect(noticeFor(Exception('boom')), expected(l10n.error_causeUnknown));
      expect(noticeFor(_fb('aborted')), expected(l10n.error_causeUnknown));
    });
  });

  group('composeErrorNotice', () {
    testWidgets('states what failed, then what the user can do', (
      tester,
    ) async {
      late String message;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              message = composeErrorNotice(
                context,
                intro: "Couldn't delete the client",
                error: _fb('unavailable'),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        message,
        "Couldn't delete the client. You appear to be offline — check your "
        'connection and try again.',
      );
    });

    testWidgets('never leaks the raw error or a support tag', (tester) async {
      await pumpHost(tester);
      final message = noticeFor(_fb('permission-denied'));
      expect(message, isNot(contains('permission-denied')));
      expect(message, isNot(contains('(')));
    });
  });
}
