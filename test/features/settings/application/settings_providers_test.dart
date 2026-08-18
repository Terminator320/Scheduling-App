import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/settings/application/settings_providers.dart';

void main() {
  test('runs only the latest scheduled save', () async {
    final calls = <int>[];
    final debouncer = SettingsSaveDebouncer(
      delay: const Duration(milliseconds: 10),
    );
    addTearDown(debouncer.dispose);

    debouncer
      ..run(() async => calls.add(1))
      ..run(() async => calls.add(2));

    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(calls, [2]);
  });

  test('forwards async save failures to onError', () async {
    Object? capturedError;
    StackTrace? capturedStack;
    final debouncer = SettingsSaveDebouncer(
      delay: const Duration(milliseconds: 10),
      onError: (error, stackTrace) {
        capturedError = error;
        capturedStack = stackTrace;
      },
    );
    addTearDown(debouncer.dispose);

    debouncer.run(() async {
      throw StateError('prefs failed');
    });

    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(capturedError, isA<StateError>());
    expect(capturedStack, isNotNull);
  });
}
