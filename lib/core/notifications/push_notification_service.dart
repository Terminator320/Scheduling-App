import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:scheduling/core/logging/app_logger.dart';

/// Thin wrapper over [FirebaseMessaging] (mirrors `MediaPermissionService`):
/// injected messaging + logger, every call guarded so a plugin failure never
/// throws into a caller. Device-only — no unit tests (platform channels).
class PushNotificationService {
  PushNotificationService({FirebaseMessaging? messaging, AppLogger? logger})
    : _messaging = messaging ?? FirebaseMessaging.instance,
      _logger = logger ?? AppLogger();

  final FirebaseMessaging _messaging;
  final AppLogger _logger;

  /// Prompts for the OS notification permission (also surfaces the Android 13+
  /// POST_NOTIFICATIONS dialog). Returns true when granted (or provisional).
  Future<bool> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission();
      final status = settings.authorizationStatus;
      return status == AuthorizationStatus.authorized ||
          status == AuthorizationStatus.provisional;
    } catch (e, st) {
      _logger.warn('PUSH requestPermission failed', e, st);
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
