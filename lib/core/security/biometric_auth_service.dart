import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:scheduling/core/logging/app_logger.dart';

/// Wraps local_auth for biometric app-lock; all calls fail closed and log exceptions.
class BiometricAuthService {
  BiometricAuthService({LocalAuthentication? auth, AppLogger? logger})
    : _auth = auth ?? LocalAuthentication(),
      _logger = logger ?? AppLogger();

  final LocalAuthentication _auth;
  final AppLogger _logger;

  /// Whether the device can perform biometric (or device-credential) auth.
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e, st) {
      _logger.warn('APPLOCK isDeviceSupported failed', e, st);
      return false;
    }
  }

  /// Prompts for biometrics with device passcode fallback; returns true only on success.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } catch (e, st) {
      _logger.warn('APPLOCK authenticate failed', e, st);
      return false;
    }
  }
}

final biometricAuthServiceProvider = Provider<BiometricAuthService>(
  (ref) => BiometricAuthService(),
);
