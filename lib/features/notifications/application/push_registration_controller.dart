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

/// Pure gate (mirrors the `isAccountDeletionSignal` helper style): only active
/// employees register for push. Admins never register and are never prompted.
bool shouldRegisterPush({
  required String role,
  required String status,
  required bool signedIn,
}) => signedIn && role == 'employee' && status == 'active';

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
    if (_busy) {
      _logger.warn('PUSH sync: skipped (busy)');
      return;
    }
    final signedIn = FirebaseAuth.instance.currentUser != null;
    final doc = _ref.read(currentUserDocProvider).value ?? const {};
    final role = (doc['role'] ?? '').toString().trim();
    final status = (doc['status'] ?? '').toString().trim();
    _logger.warn('PUSH sync: signedIn=$signedIn role="$role" status="$status"');
    if (!shouldRegisterPush(role: role, status: status, signedIn: signedIn)) {
      _logger.warn('PUSH sync: gate=false (not an active employee)');
      await _refreshSub?.cancel();
      _refreshSub = null;
      return;
    }

    _busy = true;
    try {
      await _ref.read(firebaseReadyProvider.future).catchError((Object _) {});
      final service = _ref.read(pushNotificationServiceProvider);
      final granted = await service.requestPermission();
      _logger.warn('PUSH sync: permission granted=$granted');
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
      _logger.warn('PUSH sync: docId=$docId token=${token == null ? "NULL" : "ok"}');
      if (token == null) return;

      await _upsert(docId, token, uid);
      _registeredDocId = docId;
      _registeredToken = token;
      _subscribeRefresh(docId, uid);
      _logger.warn('PUSH sync: token upserted for $docId');
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
        .listen((token) {
          _registeredToken = token;
          unawaited(_upsert(docId, token, uid));
        });
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
