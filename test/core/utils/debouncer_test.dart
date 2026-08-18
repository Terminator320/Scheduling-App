import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/utils/debouncer.dart';

void main() {
  test('runs the action once after the quiet period', () async {
    final debouncer = Debouncer(const Duration(milliseconds: 40));
    var runs = 0;
    debouncer.run(() => runs++);
    expect(runs, 0); // not yet
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(runs, 1);
  });

  test('only the last rapid action within the window runs', () async {
    final debouncer = Debouncer(const Duration(milliseconds: 40));
    final calls = <int>[];
    debouncer.run(() => calls.add(1));
    await Future<void>.delayed(const Duration(milliseconds: 15));
    debouncer.run(() => calls.add(2));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(calls, [2]);
  });

  test('cancel drops a pending action', () async {
    final debouncer = Debouncer(const Duration(milliseconds: 40));
    var ran = false;
    debouncer
      ..run(() => ran = true)
      ..cancel();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(ran, isFalse);
  });

  test('dispose drops a pending action', () async {
    final debouncer = Debouncer(const Duration(milliseconds: 40));
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
}
