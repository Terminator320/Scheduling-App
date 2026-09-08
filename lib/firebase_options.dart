import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

class DefaultFirebaseOptions {
  /// Reads [key] from `--dart-define`, failing fast instead of silently handing
  /// Firebase a bogus value.
  static String _requireDefine(String key) {
    const values = {
      'IOS_API_KEY': String.fromEnvironment('IOS_API_KEY'),
      'IOS_APP_ID': String.fromEnvironment('IOS_APP_ID'),
      'MESSAGING_SENDER_ID': String.fromEnvironment('MESSAGING_SENDER_ID'),
      'PROJECT_ID': String.fromEnvironment('PROJECT_ID'),
      'STORAGE_BUCKET': String.fromEnvironment('STORAGE_BUCKET'),
    };
    final value = values[key] ?? '';
    if (value.isEmpty) {
      throw StateError(
        'Missing "$key" in --dart-define values. See README "Setup".',
      );
    }
    return value;
  }

  static final String _MESSAGING_SENDER_ID = _requireDefine(
    'MESSAGING_SENDER_ID',
  );
  static final String _PROJECT_ID = _requireDefine('PROJECT_ID');
  static final String _STORAGE_BUCKET = _requireDefine('STORAGE_BUCKET');
  static final String _IOS_API_KEY = _requireDefine('IOS_API_KEY');
  static final String _IOS_APP_ID = _requireDefine('IOS_APP_ID');

  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.android:
        throw UnsupportedError('Scheduling App is configured for iOS only.');
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for $defaultTargetPlatform.',
        );
    }
  }

  static final FirebaseOptions ios = FirebaseOptions(
    apiKey: _IOS_API_KEY,
    appId: _IOS_APP_ID,
    messagingSenderId: _MESSAGING_SENDER_ID,
    projectId: _PROJECT_ID,
    storageBucket: _STORAGE_BUCKET,
    iosBundleId: 'net.vogas.scheduling',
  );
}
