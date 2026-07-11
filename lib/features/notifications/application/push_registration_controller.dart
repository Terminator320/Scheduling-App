import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notifications/push_notification_service.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/notifications/data/fcm_token_repository.dart';

final pushNotificationServiceProvider = Provider<PushNotificationService>(
  (ref) => PushNotificationService(logger: ref.watch(loggerProvider)),
);

final fcmTokenRepositoryProvider = Provider<FcmTokenRepository>(
  (ref) => FcmTokenRepository(
    firestore: ref.watch(firestoreProvider),
    logger: ref.watch(loggerProvider),
  ),
);

final pushRegistrationControllerProvider = Provider<PushRegistrationController>(
  PushRegistrationController.new,
);

/// Pure gate (mirrors the `isAccountDeletionSignal` helper style): active
/// employees AND admins register for push. Admins register so an admin who is
/// assigned to a job still receives the time-based nudges (30-min reminder,
/// overdue prompt, 6 PM digest); the server withholds change-driven pushes
/// (assigned/rescheduled/cancelled) from admins (see notification_utils.js
/// TIMED_RECIPIENT_ROLES vs CHANGE_RECIPIENT_ROLES).
bool shouldRegisterPush({
  required String role,
  required String status,
  required bool signedIn,
}) =>
    signedIn &&
    status == 'active' &&
    (role == 'employee' || role == 'admin');

/// Registers this device's FCM token for the signed-in active employee and
/// tears it down on sign-out. Driven by `main.dart` on every
/// `currentUserDocProvider` emission and on app-language change.
class PushRegistrationController {
  PushRegistrationController(this._ref);

  final Ref _ref;

  StreamSubscription<String>? _refreshSub;
  bool _busy = false;
  String? _registeredDocId;
  String? _registeredToken;

  AppLogger get _logger => _ref.read(loggerProvider);

  /// Idempotent. A no-op for admins / signed-out users. Safe to call on every
  /// account-doc emission and on language change (re-upserts the locale).
  Future<void> sync() async {
    if (_busy) return;
    final signedIn = FirebaseAuth.instance.currentUser != null;
    final doc = _ref.read(currentUserDocProvider).value ?? const {};
    final role = (doc['role'] ?? '').toString().trim();
    final status = (doc['status'] ?? '').toString().trim();
    if (!shouldRegisterPush(role: role, status: status, signedIn: signedIn)) {
      await _refreshSub?.cancel();
      _refreshSub = null;
      return;
    }

    _busy = true;
    try {
      await _ref.read(firebaseReadyProvider.future).catchError((Object _) {});
      final service = _ref.read(pushNotificationServiceProvider);
      final granted = await service.requestPermission();
      if (!granted) return;
      await service.configureForegroundPresentation();

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final match =
          await _ref.read(employeesRepositoryProvider).findUserByUid(uid);
      final docId = match?.id;
      if (docId == null) {
        _logger.warn('PUSH no users doc for uid; skip token upsert');
        return;
      }
      final token = await service.currentToken();
      if (token == null) return;

      await _upsert(docId, token, uid);
      _registeredDocId = docId;
      _registeredToken = token;
      _subscribeRefresh(docId, uid);
    } catch (e, st) {
      // Never let a registration failure escape as an uncaught async error
      // (sync() is called via `unawaited`, so an escape would be logged as a
      // fatal crash). Report it to Crashlytics as a non-fatal instead.
      _logger.warn('PUSH sync failed', e, st);
    } finally {
      _busy = false;
    }
  }

  Future<void> _upsert(String docId, String token, String uid) {
    return _ref.read(fcmTokenRepositoryProvider).upsertToken(
      userDocId: docId,
      token: token,
      platform: Platform.isIOS ? 'ios' : 'android',
      locale: AppLanguageController.instance.value == 'fr' ? 'fr' : 'en',
      uid: uid,
    );
  }

  void _subscribeRefresh(String docId, String uid) {
    _refreshSub?.cancel();
    _refreshSub = _ref
        .read(pushNotificationServiceProvider)
        .onTokenRefresh
        .listen(
          (token) {
            _registeredToken = token;
            unawaited(_upsert(docId, token, uid));
          },
          onError: (Object e, StackTrace st) =>
              _logger.warn('PUSH token refresh stream error', e, st),
        );
  }

  /// Best-effort de-registration for sign-out: delete the token doc and
  /// invalidate the FCM token. Never throws — sign-out must not be blocked.
  Future<void> unregisterCurrentDevice() async {
    try {
      final docId = _registeredDocId;
      final token = _registeredToken;
      if (docId != null && token != null) {
        await _ref
            .read(fcmTokenRepositoryProvider)
            .deleteToken(userDocId: docId, token: token);
      }
      await _ref.read(pushNotificationServiceProvider).deleteToken();
    } catch (e, st) {
      _logger.warn('PUSH unregister failed', e, st);
    } finally {
      await _refreshSub?.cancel();
      _refreshSub = null;
      _registeredDocId = null;
      _registeredToken = null;
    }
  }
}
