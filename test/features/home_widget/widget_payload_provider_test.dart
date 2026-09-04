import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/auth/application/active_user_identity_provider.dart';
import 'package:scheduling/features/home_widget/application/widget_sync_service.dart';

/// The tri-state `widgetPayloadProvider` hands `AppSyncListeners`.
///
/// The arm that mattered and was unhit: an identity read that FAILED must
/// propagate as an ERROR, never collapse into a settled null. Null means
/// "signed out — clear the home-screen widget", so treating a transient
/// Firestore failure as null wipes a working widget off the user's home screen
/// and leaves it blank until the next successful emission. It reads as a
/// three-line branch and it is the whole reason `AppSyncListeners.isUnsettled`
/// exists.
void main() {
  /// Reads the payload once the overridden identity has settled.
  Future<AsyncValue<Map<String, dynamic>?>> payloadFor(
    Future<ActiveUserIdentity?> Function(Ref ref) identity,
  ) async {
    final container = ProviderContainer(
      // `main()` disables Riverpod 3's retry globally; a bare container does
      // not inherit that, and the default exponential retry means an errored
      // FutureProvider's `.future` never completes.
      retry: (retryCount, error) => null,
      overrides: [activeUserIdentityProvider.overrideWith(identity)],
    );
    addTearDown(container.dispose);
    container
      ..listen(activeUserIdentityProvider, (_, _) {})
      ..listen(widgetPayloadProvider, (_, _) {});
    // Settle the override before reading. `pumpEventQueue()` alone leaves the
    // FutureProvider in `AsyncLoading`, and a loading identity is a THIRD
    // state — reading there would assert nothing about the error arm.
    try {
      await container.read(activeUserIdentityProvider.future);
    } on Object {
      // The error case under test; the provider records it either way.
    }
    return await Future.value(container.read(widgetPayloadProvider));
  }

  test(
    'an identity ERROR propagates as an error, not as a settled null',
    () async {
      final payload = await payloadFor((ref) async {
        throw Exception('permission-denied');
      });

      expect(payload.hasError, isTrue);
      expect(payload.hasValue, isFalse);
    },
  );

  test('a signed-out identity IS a settled null — clear the widget', () async {
    final payload = await payloadFor((ref) async => null);

    expect(payload.hasError, isFalse);
    expect(payload.hasValue, isTrue);
    expect(payload.value, isNull);
  });

  test('an unresolved identity stays LOADING, which is neither', () {
    // The third state, and the one `isUnsettled` reads: a cold start must not
    // be mistaken for a sign-out either. Read WITHOUT settling — the override
    // never completes, which is exactly the cold-start shape.
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        activeUserIdentityProvider.overrideWith(
          (ref) => Completer<ActiveUserIdentity?>().future,
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(widgetPayloadProvider, (_, _) {});

    final payload = container.read(widgetPayloadProvider);
    expect(payload.isLoading, isTrue);
    expect(payload.hasError, isFalse);
  });
}
