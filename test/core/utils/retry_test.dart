import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/utils/retry.dart';

void main() {
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
  });
}
