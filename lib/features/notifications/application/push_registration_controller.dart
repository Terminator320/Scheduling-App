import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notifications/push_notification_service.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/core/utils/reentrant_sync.dart';
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

/// The live OS notification-authorization status, read without prompting the
/// user. Invalidate this to re-read it after permissions change.
final notificationAuthStatusProvider =
    FutureProvider.autoDispose<AuthorizationStatus>(
      (ref) => ref.watch(pushNotificationServiceProvider).authorizationStatus(),
    );

/// Gate for push registration: active employees and admins (admins register for timed nudges; server withholds change-driven pushes from them).
bool shouldRegisterPush({
  required String role,
  required String status,
  required bool signedIn,
}) => signedIn && status == 'active' && (role == 'employee' || role == 'admin');

/// Registers this device's FCM token for the signed-in active employee and
/// tears it down on sign-out; driven by `main.dart` on every
/// `currentUserDocProvider` emission and on app-language change.
class PushRegistrationController with ReentrantSync {
  PushRegistrationController(this._ref, {FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final Ref _ref;
  final FirebaseAuth _auth;

  StreamSubscription<String>? _refreshSub;
  String? _registeredDocId;
  String? _registeredToken;
  String? _registeredUid;
  String? _registeredLocale;

  AppLogger get _logger => _ref.read(loggerProvider);

  static String _currentLocale() =>
      AppLanguageController.instance.value == 'fr' ? 'fr' : 'en';

  /// Idempotent and safe to call on every account-doc emission or language change; concurrent calls coalesce so latest state wins.
  Future<void> sync() => runCoalesced(_syncGuarded);

  Future<void> _syncGuarded() async {
    final signedIn = _auth.currentUser != null;
    final doc = _ref.read(currentUserDocProvider).value ?? const {};
    final role = (doc['role'] ?? '').toString().trim();
    final status = (doc['status'] ?? '').toString().trim();
    if (!shouldRegisterPush(role: role, status: status, signedIn: signedIn)) {
      await _refreshSub?.cancel();
      _refreshSub = null;
      return;
    }

    final uid = _auth.currentUser?.uid;
    final locale = _currentLocale();
    // Fast path: already registered for this uid+locale with live refresh subscription; skip query and upsert.
    if (uid != null &&
        uid == _registeredUid &&
        locale == _registeredLocale &&
        _refreshSub != null) {
      return;
    }

    try {
      await _ref.read(firebaseReadyProvider.future).catchError((Object _) {});
      final service = _ref.read(pushNotificationServiceProvider);
      final granted = await service.requestPermission();
      if (!granted) return;
      await service.configureForegroundPresentation();

      if (uid == null) return;
      final match = await _ref
          .read(employeesRepositoryProvider)
          .findUserByUid(uid);
      final docId = match?.id;
      if (docId == null) {
        _logger.warn('PUSH no users doc for uid; skip token upsert');
        return;
      }
      final token = await service.currentToken();
      if (token == null) return;

      await _upsert(docId, token, uid, locale);
      _registeredDocId = docId;
      _registeredToken = token;
      _registeredUid = uid;
      _registeredLocale = locale;
      _subscribeRefresh(docId, uid);
    } catch (e, st) {
      // Don't let registration failure escape as uncaught async error (sync() is unawaited); log as non-fatal instead.
      _logger.warn('PUSH sync failed', e, st);
    }
  }

  Future<void> _upsert(String docId, String token, String uid, String locale) {
    return _ref
        .read(fcmTokenRepositoryProvider)
        .upsertToken(
          userDocId: docId,
          token: token,
          platform: Platform.isIOS ? 'ios' : 'android',
          locale: locale,
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
            unawaited(_upsert(docId, token, uid, _currentLocale()));
          },
          onError: (Object e, StackTrace st) =>
              _logger.warn('PUSH token refresh stream error', e, st),
        );
  }

  /// Best-effort de-registration for sign-out — deletes the token doc and
  /// invalidates the FCM token; never throws, so sign-out is never blocked.
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
      _registeredUid = null;
      _registeredLocale = null;
    }
  }
}
