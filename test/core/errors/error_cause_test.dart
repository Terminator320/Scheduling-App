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

  // Classification is exercised through the public composeErrorNotice — the
  // classifier itself is private to error_cause.dart.
  late String Function(Object error) noticeFor;

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            noticeFor = (error) => composeErrorNotice(
              context,
              intro: 'Intro',
              tag: 'TAG',
              error: error,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  String expected(String cause) => l10n.error_noticeWithCause(
    'Intro',
    cause,
    'TAG',
  );

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

    testWidgets('anything else maps to unknown', (tester) async {
      await pumpHost(tester);
      expect(noticeFor(Exception('boom')), expected(l10n.error_causeUnknown));
      expect(noticeFor(_fb('aborted')), expected(l10n.error_causeUnknown));
    });
  });

  group('composeErrorNotice', () {
    testWidgets('formats intro, cause, and tag', (tester) async {
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
                tag: 'CLI-DEL',
                error: _fb('unavailable'),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        message,
        "Couldn't delete the client — you appear to be offline. (CLI-DEL)",
      );
    });
  });
}
