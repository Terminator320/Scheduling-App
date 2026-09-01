import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/security/biometric_auth_service.dart';

class _MockLocalAuth extends Mock implements LocalAuthentication {}

class _RecordingLogger extends AppLogger {
  final warnings = <String>[];

  @override
  void warn(String message, [Object? error, StackTrace? stack]) =>
      warnings.add(message);
}

/// The real `BiometricAuthService` was never instantiated in a test, and both
/// its methods are `catch → log → return false`.
///
/// `.claude/rules/error-handling.md` singles that shape out as the easiest
/// failure to miss: *"a fail-closed `catch (_) { return false; }` ... hides a
/// permanently-broken plugin channel behind a feature that just 'doesn't
/// work'."* Here the feature is the biometric app lock. If `local_auth` starts
/// throwing on this device, `isAvailable()` returns false forever, the lock
/// silently never engages, and the ONLY trace is the warn — so the warn is as
/// much the contract as the return value, and both are asserted below.
///
/// The constructor already accepts both dependencies, so this costs nothing
/// but the file.
void main() {
  late _MockLocalAuth auth;
  late _RecordingLogger logger;
  late BiometricAuthService service;

  setUp(() {
    auth = _MockLocalAuth();
    logger = _RecordingLogger();
    service = BiometricAuthService(auth: auth, logger: logger);
  });

  group('isAvailable', () {
    test('reports what the plugin reports', () async {
      when(() => auth.isDeviceSupported()).thenAnswer((_) async => true);
      expect(await service.isAvailable(), isTrue);

      when(() => auth.isDeviceSupported()).thenAnswer((_) async => false);
      expect(await service.isAvailable(), isFalse);
      expect(logger.warnings, isEmpty);
    });

    test('fails CLOSED on a throw, and logs it under APPLOCK', () async {
      when(() => auth.isDeviceSupported()).thenThrow(Exception('no channel'));

      expect(await service.isAvailable(), isFalse);
      // The tag is the only way this reaches Crashlytics, and the registry in
      // `.claude/rules/error-handling.md` is keyed on it.
      expect(logger.warnings.single, startsWith('APPLOCK'));
    });
  });

  group('authenticate', () {
    test('returns true only when the prompt succeeds', () async {
      when(
        () => auth.authenticate(
          localizedReason: any(named: 'localizedReason'),
          persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
        ),
      ).thenAnswer((_) async => true);

      expect(await service.authenticate('unlock'), isTrue);
      expect(logger.warnings, isEmpty);
    });

    test('a declined prompt is false and is NOT logged', () async {
      // A user dismissing the sheet is an ordinary outcome, not a defect —
      // logging it would file noise for every cancelled unlock.
      when(
        () => auth.authenticate(
          localizedReason: any(named: 'localizedReason'),
          persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
        ),
      ).thenAnswer((_) async => false);

      expect(await service.authenticate('unlock'), isFalse);
      expect(logger.warnings, isEmpty);
    });

    test('fails CLOSED on a throw, and logs it under APPLOCK', () async {
      when(
        () => auth.authenticate(
          localizedReason: any(named: 'localizedReason'),
          persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
        ),
      ).thenThrow(Exception('no channel'));

      expect(await service.authenticate('unlock'), isFalse);
      expect(logger.warnings.single, startsWith('APPLOCK'));
    });

    test('passes the reason through and keeps the backgrounding flag on',
        () async {
      // `persistAcrossBackgrounding: true` is what stops the prompt being
      // cancelled when iOS puts the app behind the biometric sheet.
      when(
        () => auth.authenticate(
          localizedReason: any(named: 'localizedReason'),
          persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
        ),
      ).thenAnswer((_) async => true);

      await service.authenticate('Unlock Eau Secours');

      verify(
        () => auth.authenticate(
          localizedReason: 'Unlock Eau Secours',
          persistAcrossBackgrounding: true,
        ),
      ).called(1);
    });
  });
}
