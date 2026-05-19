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
  group('classifyError', () {
    test('network-ish Firebase codes map to offline', () {
      expect(classifyError(_fb('unavailable')), ErrorCause.offline);
      expect(classifyError(_fb('network-request-failed')), ErrorCause.offline);
      expect(classifyError(_fb('deadline-exceeded')), ErrorCause.offline);
    });

    test('permission-denied maps to permissionDenied', () {
      expect(
        classifyError(_fb('permission-denied')),
        ErrorCause.permissionDenied,
      );
    });

    test('not-found maps to notFound', () {
      expect(classifyError(_fb('not-found')), ErrorCause.notFound);
    });

    test('socket and timeout exceptions map to offline', () {
      expect(classifyError(const SocketException('x')), ErrorCause.offline);
      expect(classifyError(TimeoutException('x')), ErrorCause.offline);
    });

    test('anything else maps to unknown', () {
      expect(classifyError(Exception('boom')), ErrorCause.unknown);
      expect(classifyError(_fb('aborted')), ErrorCause.unknown);
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
