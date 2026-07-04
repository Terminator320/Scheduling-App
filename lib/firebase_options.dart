import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DefaultFirebaseOptions {
  /// Reads [key] from dev/.env, failing fast instead of silently handing
  /// Firebase a bogus value (which would surface later as opaque auth or
  /// network errors).
  static String _requireEnv(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError(
        'Missing "$key" in dev/.env — copy dev/.env.example to dev/.env '
        'and fill in the Firebase values (see README "Setup").',
      );
    }
    return value;
  }

  static final String _FIREBASE_API_KEY = _requireEnv('FIREBASE_API_KEY');
  static final String _APP_ID = _requireEnv('APP_ID');
  static final String _MESSAGING_SENDER_ID = _requireEnv(
    'MESSAGING_SENDER_ID',
  );
  static final String _PROJECT_ID = _requireEnv('PROJECT_ID');
  static final String _STORAGE_BUCKET = _requireEnv('STORAGE_BUCKET');
  static final String _IOS_API_KEY = _requireEnv('IOS_API_KEY');
  static final String _IOS_APP_ID = _requireEnv('IOS_APP_ID');

  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for $defaultTargetPlatform.',
        );
    }
  }

  static final FirebaseOptions android = FirebaseOptions(
    apiKey: _FIREBASE_API_KEY,
    appId: _APP_ID,
    messagingSenderId: _MESSAGING_SENDER_ID,
    projectId: _PROJECT_ID,
    storageBucket: _STORAGE_BUCKET,
  );

  static final FirebaseOptions ios = FirebaseOptions(
    apiKey: _IOS_API_KEY,
    appId: _IOS_APP_ID,
    messagingSenderId: _MESSAGING_SENDER_ID,
    projectId: _PROJECT_ID,
    storageBucket: _STORAGE_BUCKET,
    iosBundleId: 'net.vogas.scheduling',
  );
}
