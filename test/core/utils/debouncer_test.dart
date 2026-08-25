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

void main() {
  test('runs the action once after the quiet period', () async {
    final debouncer = Debouncer(
      const Duration(milliseconds: 40),
      onError: (_, _) {},
    );
    var runs = 0;
    debouncer.run(() => runs++);
    expect(runs, 0); // not yet
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(runs, 1);
  });

  test('only the last rapid action within the window runs', () async {
    final debouncer = Debouncer(
      const Duration(milliseconds: 40),
      onError: (_, _) {},
    );
    final calls = <int>[];
    debouncer.run(() => calls.add(1));
    await Future<void>.delayed(const Duration(milliseconds: 15));
    debouncer.run(() => calls.add(2));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(calls, [2]);
  });

  test('cancel drops a pending action', () async {
    final debouncer = Debouncer(
      const Duration(milliseconds: 40),
      onError: (_, _) {},
    );
    var ran = false;
    debouncer
      ..run(() => ran = true)
      ..cancel();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(ran, isFalse);
  });

  test('dispose drops a pending action', () async {
    final debouncer = Debouncer(
      const Duration(milliseconds: 40),
      onError: (_, _) {},
    );
    var ran = false;
    debouncer
      ..run(() => ran = true)
      ..dispose();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(ran, isFalse);
  });

  test('forwards async action failures to onError', () async {
    Object? capturedError;
    StackTrace? capturedStack;
    final debouncer = Debouncer(
      const Duration(milliseconds: 40),
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

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(capturedError, isA<StateError>());
    expect(capturedStack, isNotNull);
  });

  test('a synchronous throw is reported, never swallowed', () async {
    // B2: `onError` used to be optional and five of six call sites omitted it,
    // so a failed debounced search vanished with nothing logged anywhere.
    Object? capturedError;
    final debouncer = Debouncer(
      const Duration(milliseconds: 40),
      onError: (error, _) => capturedError = error,
    );

    expect(
      () => debouncer.run(() => throw StateError('sync boom')),
      returnsNormally,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(capturedError, isA<StateError>());
  });

  group('Debouncer.tagged', () {
    // The factory every call site is required to use. `onError` being required
    // closed the "forgot to handle it" case; what `tagged` closes is WHERE the
    // logger is resolved — an argument is evaluated at the CONSTRUCTION site,
    // so a lazy handler reading `ref` from inside the callback cannot be
    // written through this door. The one site that deviated shipped a FATAL,
    // and until now nothing exercised the factory at all.
    test('routes a failed action into the logger under its tag', () async {
      final logger = _RecordingLogger();
      Debouncer.tagged(
        const Duration(milliseconds: 40),
        logger: logger,
        tag: 'CLI-SEARCH debounced client search failed',
      ).run(() => throw StateError('boom'));

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(logger.calls, hasLength(1));
      expect(
        logger.calls.single.message,
        'CLI-SEARCH debounced client search failed',
      );
      expect(logger.calls.single.error, isA<StateError>());
    });

    test('an ASYNC rejection is logged too, not just a sync throw', () async {
      // The action runs from a Timer callback, so there is no caller left to
      // catch either shape.
      final logger = _RecordingLogger();
      Debouncer.tagged(
        const Duration(milliseconds: 40),
        logger: logger,
        tag: 'HIST-SEARCH failed',
      ).run(() async => throw StateError('async boom'));

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(logger.calls.single.error, isA<StateError>());
    });

    test('a successful action logs nothing', () async {
      final logger = _RecordingLogger();
      final debouncer = Debouncer.tagged(
        const Duration(milliseconds: 40),
        logger: logger,
        tag: 'CLI-SEARCH debounced client search failed',
      );

      var runs = 0;
      debouncer.run(() => runs++);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(runs, 1);
      expect(logger.calls, isEmpty);
    });

    test('a cancelled action never runs and never logs', () async {
      final logger = _RecordingLogger();
      Debouncer.tagged(
        const Duration(milliseconds: 40),
        logger: logger,
        tag: 'CLI-SEARCH debounced client search failed',
      )
        ..run(() => throw StateError('should not run'))
        ..cancel();

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(logger.calls, isEmpty);
    });
  });
}
