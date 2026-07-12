import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:scheduling/core/logging/app_logger.dart';

/// Thin wrapper over [FirebaseMessaging] (mirrors `MediaPermissionService`):
/// injected messaging + logger, every call guarded so a plugin failure never
/// throws into a caller. Device-only — no unit tests (platform channels).
class PushNotificationService {
  PushNotificationService({FirebaseMessaging? messaging, AppLogger? logger})
    : _injectedMessaging = messaging,
      _logger = logger ?? AppLogger();

  final FirebaseMessaging? _injectedMessaging;
  final AppLogger _logger;

  // Resolve `FirebaseMessaging.instance` lazily rather than in the constructor:
  // the Settings notifications row reads this service at build time, and an
  // eager `.instance` throws when Firebase isn't initialized (e.g. widget
  // tests). Every use below already sits inside a guarded try, so a lazy throw
  // degrades to the safe default instead of a crash.
  FirebaseMessaging get _messaging =>
      _injectedMessaging ?? FirebaseMessaging.instance;

  /// Prompts for the OS notification permission (also surfaces the Android 13+
  /// POST_NOTIFICATIONS dialog). Returns true when granted (or provisional).
  Future<bool> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission();
      return isGranted(settings.authorizationStatus);
    } catch (e, st) {
      _logger.warn('PUSH requestPermission failed', e, st);
      return false;
    }
  }

  /// The OS-level authorization status WITHOUT prompting (unlike
  /// [requestPermission], which shows the one-time system dialog). Used by the
  /// Settings notifications row to render On/Off and decide whether tapping
  /// should re-prompt or deep-link to system Settings. Defaults to
  /// [AuthorizationStatus.notDetermined] on failure so the UI offers the
  /// enable action rather than a misleading "On".
  Future<AuthorizationStatus> authorizationStatus() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      return settings.authorizationStatus;
    } catch (e, st) {
      _logger.warn('PUSH getNotificationSettings failed', e, st);
      return AuthorizationStatus.notDetermined;
    }
  }

  /// True when notifications are authorized (or provisional) — the shared
  /// predicate behind [requestPermission] and [authorizationStatus] so the
  /// "granted" definition stays in one place.
  static bool isGranted(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  /// Opens the OS Settings page for this app. On iOS the system notification
  /// prompt only ever appears ONCE per install, so a user who dismissed or
  /// denied it (or updated from a build that never asked) can only re-enable
  /// notifications here — there is no way to re-show the dialog from code.
  Future<bool> openSystemSettings() async {
    try {
      return await openAppSettings();
    } catch (e, st) {
      _logger.warn('PUSH openAppSettings failed', e, st);
      return false;
    }
  }

  /// iOS foreground banners: without this, a notification received while the
  /// app is foregrounded shows nothing on iOS.
  Future<void> configureForegroundPresentation() async {
    try {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e, st) {
      _logger.warn('PUSH foreground options failed', e, st);
    }
  }

  /// The device FCM token, or null on failure. On iOS the APNS token must
  /// resolve first (brief retry if it's momentarily null), else `getToken()`
  /// returns null.
  Future<String?> currentToken() async {
    try {
      if (Platform.isIOS) {
        var apns = await _messaging.getAPNSToken();
        if (apns == null) {
          await Future<void>.delayed(const Duration(seconds: 2));
          apns = await _messaging.getAPNSToken();
        }
        if (apns == null) {
          _logger.warn('PUSH no APNS token yet');
          return null;
        }
      }
      return await _messaging.getToken();
    } catch (e, st) {
      _logger.warn('PUSH getToken failed', e, st);
      return null;
    }
  }

  /// Emits a fresh token whenever FCM rotates it.
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  /// The message that launched the app from a terminated state (tap), if any.
  Future<RemoteMessage?> initialMessage() => _messaging.getInitialMessage();

  /// Fired when a background (not terminated) notification is tapped.
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  /// Invalidates the device token (used on sign-out).
  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
    } catch (e, st) {
      _logger.warn('PUSH deleteToken failed', e, st);
    }
  }
}
