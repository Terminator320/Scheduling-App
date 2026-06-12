import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DefaultFirebaseOptions {
  static final String _FIREBASE_API_KEY =
      dotenv.env['FIREBASE_API_KEY'] ?? 'default_key';
  static final String _APP_ID = dotenv.env['APP_ID'] ?? 'default_key';
  static final String _MESSAGING_SENDER_ID =
      dotenv.env['MESSAGING_SENDER_ID'] ?? 'default_key';
  static final String _PROJECT_ID = dotenv.env['PROJECT_ID'] ?? 'default_key';
  static final String _STORAGE_BUCKET =
      dotenv.env['STORAGE_BUCKET'] ?? 'default_key';
  static final String _IOS_API_KEY = dotenv.env['IOS_API_KEY'] ?? 'default_key';
  static final String _IOS_APP_ID = dotenv.env['IOS_APP_ID'] ?? 'default_key';

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
