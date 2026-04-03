import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

import 'package:flutter_dotenv/flutter_dotenv.dart';


class DefaultFirebaseOptions {
  static String _FIREBASE_API_KEY = dotenv.env['FIREBASE_API_KEY'] ?? 'default_key';
  static String _APP_ID = dotenv.env['APP_ID'] ?? 'default_key';
  static String _MESSAGING_SENDER_ID = dotenv.env['MESSAGING_SENDER_ID'] ?? 'default_key';
  static String _PROJECT_ID = dotenv.env['PROJECT_ID'] ?? 'default_key';
  static String _STORAGE_BUCKET = dotenv.env['STORAGE_BUCKET'] ?? 'default_key';


  static final FirebaseOptions android = FirebaseOptions(
    apiKey: _FIREBASE_API_KEY,
    appId: _APP_ID,
    messagingSenderId: _MESSAGING_SENDER_ID,
    projectId: _PROJECT_ID,
    storageBucket: _STORAGE_BUCKET,
  );

}
