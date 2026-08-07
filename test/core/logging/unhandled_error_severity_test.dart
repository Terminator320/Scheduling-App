import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/logging/unhandled_error_severity.dart';

void main() {
  test('an unhandled Firestore permission-denied is not a crash', () {
    expect(
      isFatalUnhandledError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      ),
      isFalse,
    );
  });

  test('other Firebase failures stay fatal', () {
    expect(
      isFatalUnhandledError(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      ),
      isTrue,
    );
  });

  // Storage rules deny on teardown for the same reason Firestore's do.
  test('a permission-denied from another Firebase plugin is not a crash', () {
    expect(
      isFatalUnhandledError(
        FirebaseException(
          plugin: 'firebase_storage',
          code: 'permission-denied',
        ),
      ),
      isFalse,
    );
  });

  test('a plain error stays fatal', () {
    expect(isFatalUnhandledError(StateError('boom')), isTrue);
  });
}
