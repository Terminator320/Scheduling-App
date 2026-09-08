import 'package:fake_async/fake_async.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/utils/retry.dart';

void main() {
  group('isAuthPropagationDenied', () {
    test('accepts a Firestore permission-denied', () {
      expect(
        isAuthPropagationDenied(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        ),
        isTrue,
      );
    });

    test('rejects another Firestore code', () {
      expect(
        isAuthPropagationDenied(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        isFalse,
      );
    });

    test('rejects a FirebaseAuthException', () {
      expect(
        isAuthPropagationDenied(FirebaseAuthException(code: 'wrong-password')),
        isFalse,
      );
    });

    test('rejects a non-Firebase error', () {
      expect(isAuthPropagationDenied(Exception('nope')), isFalse);
    });
  });

  group('retryAsync', () {
    test('returns first-attempt value without delay', () {
      fakeAsync((async) {
        var attempts = 0;
        Object? result;

        retryAsync<String>(() async {
          attempts++;
          return 'ok';
        }, delays: const [Duration(milliseconds: 500)]).then((v) => result = v);

        async.flushMicrotasks();
        expect(attempts, 1);
        expect(result, 'ok');
      });
    });

    test('retries with the supplied delays then succeeds', () {
      fakeAsync((async) {
        var attempts = 0;
        Object? result;

        retryAsync<int>(
          () async {
            attempts++;
            if (attempts < 3) throw StateError('flaky');
            return 42;
          },
          retryWhen: (e) => e is StateError,
          delays: const [
            Duration(milliseconds: 500),
            Duration(milliseconds: 1500),
          ],
        ).then((v) => result = v);

        async.elapse(const Duration(milliseconds: 499));
        expect(attempts, 1);
        async.elapse(const Duration(milliseconds: 1));
        expect(attempts, 2);
        async.elapse(const Duration(milliseconds: 1500));
        expect(attempts, 3);
        expect(result, 42);
      });
    });

    test('rethrows the final exception when all attempts fail', () {
      fakeAsync((async) {
        var attempts = 0;
        Object? caught;

        retryAsync<void>(
          () async {
            attempts++;
            throw StateError('attempt $attempts');
          },
          retryWhen: (e) => e is StateError,
          delays: const [
            Duration(milliseconds: 500),
            Duration(milliseconds: 1500),
          ],
        ).catchError((Object e) => caught = e);

        async.elapse(const Duration(seconds: 5));
        expect(attempts, 3);
        expect(caught, isA<StateError>());
        expect((caught! as StateError).message, 'attempt 3');
      });
    });

    test('invokes onRetry with attempt number and error per retry', () {
      fakeAsync((async) {
        final retries = <(int, String)>[];

        retryAsync<void>(
          () async {
            throw StateError('boom');
          },
          retryWhen: (e) => e is StateError,
          delays: const [
            Duration(milliseconds: 10),
            Duration(milliseconds: 20),
          ],
          onRetry: (attempt, e, _) =>
              retries.add((attempt, (e as StateError).message)),
        ).catchError((_) {});

        async.elapse(const Duration(seconds: 1));
        expect(retries, [(1, 'boom'), (2, 'boom')]);
      });
    });

    test('retries a permission-denied on the default predicate', () {
      fakeAsync((async) {
        var attempts = 0;
        Object? result;

        retryAsync<String>(() async {
          attempts++;
          if (attempts < 3) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
            );
          }
          return 'ok';
        }).then((v) => result = v);

        async.elapse(kAuthPropagationDelays.first);
        expect(attempts, 2);
        async.elapse(const Duration(seconds: 5));
        expect(attempts, 3);
        expect(result, 'ok');
      });
    });

    test('does not retry a non-propagation Firestore error', () {
      fakeAsync((async) {
        var attempts = 0;
        Object? caught;

        retryAsync<void>(() async {
          attempts++;
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'unavailable',
          );
        }).catchError((Object e) => caught = e);

        async.elapse(const Duration(seconds: 10));
        expect(attempts, 1);
        expect((caught! as FirebaseException).code, 'unavailable');
      });
    });
  });

  group('retryStream', () {
    test('re-subscribes on a retryable error then yields the values', () {
      fakeAsync((async) {
        var subscriptions = 0;
        final emitted = <int>[];

        retryStream<int>(
          () {
            subscriptions++;
            if (subscriptions < 3) {
              return Stream<int>.error(StateError('not ready'));
            }
            return Stream<int>.fromIterable([1, 2]);
          },
          retryWhen: (e) => e is StateError,
          delays: const [
            Duration(milliseconds: 400),
            Duration(milliseconds: 1200),
          ],
        ).listen(emitted.add);

        async.elapse(const Duration(seconds: 3));
        expect(subscriptions, 3);
        expect(emitted, [1, 2]);
      });
    });

    test('does not retry an error the predicate rejects', () {
      fakeAsync((async) {
        var subscriptions = 0;
        Object? caught;

        retryStream<int>(
          () {
            subscriptions++;
            return Stream<int>.error(ArgumentError('nope'));
          },
          retryWhen: (e) => e is StateError,
          delays: const [Duration(milliseconds: 400)],
        ).listen(null, onError: (Object e) => caught = e);

        async.elapse(const Duration(seconds: 2));
        expect(subscriptions, 1);
        expect(caught, isA<ArgumentError>());
      });
    });

    test('surfaces the error after exhausting every retry', () {
      fakeAsync((async) {
        var subscriptions = 0;
        Object? caught;

        retryStream<int>(
          () {
            subscriptions++;
            return Stream<int>.error(StateError('still down'));
          },
          retryWhen: (e) => e is StateError,
          delays: const [
            Duration(milliseconds: 400),
            Duration(milliseconds: 1200),
          ],
        ).listen(null, onError: (Object e) => caught = e);

        async.elapse(const Duration(seconds: 5));
        expect(subscriptions, 3);
        expect(caught, isA<StateError>());
      });
    });

    test(
      're-subscribes on a permission-denied under the default predicate',
      () {
        fakeAsync((async) {
          var subscriptions = 0;
          final emitted = <int>[];

          retryStream<int>(() {
            subscriptions++;
            if (subscriptions < 2) {
              return Stream<int>.error(
                FirebaseException(
                  plugin: 'cloud_firestore',
                  code: 'permission-denied',
                ),
              );
            }
            return Stream<int>.fromIterable([7]);
          }).listen(emitted.add);

          async.elapse(const Duration(seconds: 5));
          expect(subscriptions, 2);
          expect(emitted, [7]);
        });
      },
    );
  });
}
