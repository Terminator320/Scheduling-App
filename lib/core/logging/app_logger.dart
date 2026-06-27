import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

class AppLogger {
  AppLogger({Logger? logger, FirebaseCrashlytics? crashlytics})
    : _logger = logger ?? Logger(printer: PrettyPrinter(methodCount: 0)),
      _crashlyticsOverride = crashlytics;

  final Logger _logger;
  final FirebaseCrashlytics? _crashlyticsOverride;

  FirebaseCrashlytics get _crashlytics =>
      _crashlyticsOverride ?? FirebaseCrashlytics.instance;

  void warn(String message, [Object? error, StackTrace? stack]) {
    if (kDebugMode) _logger.w(message, error: error, stackTrace: stack);
    if (kReleaseMode) {
      _crashlytics.log(message);
      if (error != null) {
        _crashlytics.recordError(error, stack);
      }
    }
  }
}

final loggerProvider = Provider<AppLogger>((ref) => AppLogger());
