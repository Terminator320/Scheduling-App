import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/app/device_deregistration.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/feedback/error_snack_bar.dart';

final accountExitControllerProvider = Provider<AccountExitController>(
  (ref) => AccountExitController(
    logger: ref.read(loggerProvider),
    authService: ref.read(authServiceProvider),
    deregisterDevice: () => deregisterThisDevice(
      DeviceDeregistrationDeps.fromRef(ref),
    ),
    isSignedIn: () => ref.read(firebaseAuthProvider).currentUser != null,
  ),
);

/// Orchestrates a forced sign-out caused by server-side account changes.
///
/// Detection stays in listeners; teardown, navigation, and the reentrancy guard
/// live here so every forced-exit path shares one owner.
class AccountExitController {
  AccountExitController({
    required AppLogger logger,
    required AuthService authService,
    required Future<void> Function() deregisterDevice,
    required bool Function() isSignedIn,
  }) : _logger = logger,
       _authService = authService,
       _deregisterDevice = deregisterDevice,
       _isSignedIn = isSignedIn;

  final AppLogger _logger;
  final AuthService _authService;
  final Future<void> Function() _deregisterDevice;
  final bool Function() _isSignedIn;
  bool _isHandlingAccountExit = false;

  /// De-registers this device, signs out, and lands on login with a notice.
  ///
  /// The order matters: push, presence and Live Activity registration are all
  /// torn down BEFORE `signOut()`, because each needs the credential that
  /// sign-out revokes. Each is best-effort; a failure there must not block the
  /// sign-out, which is the part that actually protects the user.
  Future<void> exitAccount({
    required String Function(AppLocalizations) selectMessage,
    required GlobalKey<NavigatorState> navigatorKey,
    required GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey,
    required bool Function() isMounted,
  }) async {
    if (_isHandlingAccountExit) return;
    if (!_isSignedIn()) return;

    final navContext = navigatorKey.currentContext;
    if (navContext == null) return;
    _isHandlingAccountExit = true;

    var exitScheduled = false;
    try {
      final message = selectMessage(AppLocalizations.of(navContext));
      await _deregisterDevice();
      await _authService.signOut();
      if (!isMounted()) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isMounted()) {
          _isHandlingAccountExit = false;
          return;
        }
        final messengerContext = scaffoldMessengerKey.currentContext;
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          AppRoutes.login,
          (_) => false,
        );
        scaffoldMessengerKey.currentState?.showSnackBar(
          errorSnackBar(messengerContext ?? navContext, message),
        );
        _isHandlingAccountExit = false;
      });
      exitScheduled = true;
    } catch (e, st) {
      _logger.warn('ACCOUNT-EXIT sign-out failed', e, st);
    } finally {
      if (!exitScheduled) _isHandlingAccountExit = false;
    }
  }
}
