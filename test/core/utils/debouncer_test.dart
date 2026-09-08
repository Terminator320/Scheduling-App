import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/utils/debouncer.dart';

/// Records what `Debouncer.tagged` routes into `AppLogger.warn`.
class _RecordingLogger extends AppLogger {
  final calls = <({String message, Object? error})>[];

  @override
  void warn(String message, [Object? error, StackTrace? stack]) {
    calls.add((message: message, error: error));
  }
}

/// Every test here drives a `Timer` through `fake_async` rather than a real
/// wall clock: a 40 ms window with an 80 ms sleep left a 40 ms margin that
/// full-suite CPU contention exceeded, so the file went red roughly one run
/// in ten with nothing wrong.
const _window = Duration(milliseconds: 40);
const _past = Duration(milliseconds: 80);

void main() {
  test('runs the action once after the quiet period', () {
    fakeAsync((async) {
      final debouncer = Debouncer(_window, onError: (_, _) {});
      var runs = 0;
      debouncer.run(() => runs++);
      expect(runs, 0); // not yet
      async.elapse(_past);
      expect(runs, 1);
    });
  });

  test('only the last rapid action within the window runs', () {
    fakeAsync((async) {
      final debouncer = Debouncer(_window, onError: (_, _) {});
      final calls = <int>[];
      debouncer.run(() => calls.add(1));
      async.elapse(const Duration(milliseconds: 15));
      debouncer.run(() => calls.add(2));
      async.elapse(_past);
      expect(calls, [2]);
    });
  });

  test('cancel drops a pending action', () {
    fakeAsync((async) {
      final debouncer = Debouncer(_window, onError: (_, _) {});
      var ran = false;
      debouncer
        ..run(() => ran = true)
        ..cancel();
      async.elapse(_past);
      expect(ran, isFalse);
    });
  });

  test('dispose drops a pending action', () {
    fakeAsync((async) {
      final debouncer = Debouncer(_window, onError: (_, _) {});
      var ran = false;
      debouncer
        ..run(() => ran = true)
        ..dispose();
      async.elapse(_past);
      expect(ran, isFalse);
    });
  });

  test('forwards async action failures to onError', () {
    fakeAsync((async) {
      Object? capturedError;
      StackTrace? capturedStack;
      final debouncer = Debouncer(
        _window,
        onError: (error, stackTrace) {
          capturedError = error;
          capturedStack = stackTrace;
        },
      );

      expect(
        () => debouncer.run(() async {
          throw StateError('boom');
        }),
        returnsNormally,
      );

      async.elapse(_past);

      expect(capturedError, isA<StateError>());
      expect(capturedStack, isNotNull);
    });
  });

  test('a synchronous throw is reported, never swallowed', () {
    // B2: `onError` used to be optional and five of six call sites omitted it,
    // so a failed debounced search vanished with nothing logged anywhere.
    fakeAsync((async) {
      Object? capturedError;
      final debouncer = Debouncer(
        _window,
        onError: (error, _) => capturedError = error,
      );

      expect(
        () => debouncer.run(() => throw StateError('sync boom')),
        returnsNormally,
      );
      async.elapse(_past);

      expect(capturedError, isA<StateError>());
    });
  });

  group('Debouncer.tagged', () {
    // The factory every call site is required to use. `onError` being required
    // closed the "forgot to handle it" case; what `tagged` closes is WHERE the
    // logger is resolved — an argument is evaluated at the CONSTRUCTION site,
    // so a lazy handler reading `ref` from inside the callback cannot be
    // written through this door. The one site that deviated shipped a FATAL,
    // and until now nothing exercised the factory at all.
    test('routes a failed action into the logger under its tag', () {
      fakeAsync((async) {
        final logger = _RecordingLogger();
        Debouncer.tagged(
          _window,
          logger: logger,
          tag: 'CLI-SEARCH debounced client search failed',
        ).run(() => throw StateError('boom'));

        async.elapse(_past);

        expect(logger.calls, hasLength(1));
        expect(
          logger.calls.single.message,
          'CLI-SEARCH debounced client search failed',
        );
        expect(logger.calls.single.error, isA<StateError>());
      });
    });

    test('an ASYNC rejection is logged too, not just a sync throw', () {
      // The action runs from a Timer callback, so there is no caller left to
      // catch either shape.
      fakeAsync((async) {
        final logger = _RecordingLogger();
        Debouncer.tagged(
          _window,
          logger: logger,
          tag: 'HIST-SEARCH failed',
        ).run(() async => throw StateError('async boom'));

        async.elapse(_past);

        expect(logger.calls.single.error, isA<StateError>());
      });
    });

    test('a successful action logs nothing', () {
      fakeAsync((async) {
        final logger = _RecordingLogger();
        final debouncer = Debouncer.tagged(
          _window,
          logger: logger,
          tag: 'CLI-SEARCH debounced client search failed',
        );

        var runs = 0;
        debouncer.run(() => runs++);
        async.elapse(_past);

        expect(runs, 1);
        expect(logger.calls, isEmpty);
      });
    });

    test('a cancelled action never runs and never logs', () {
      fakeAsync((async) {
        final logger = _RecordingLogger();
        Debouncer.tagged(
          _window,
          logger: logger,
          tag: 'CLI-SEARCH debounced client search failed',
        )
          ..run(() => throw StateError('should not run'))
          ..cancel();

        async.elapse(_past);

        expect(logger.calls, isEmpty);
      });
    });
  });
}
