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

  // Lazy lookup so tests that never enter release branches don't have to
  // initialize Firebase just to instantiate the logger.
  FirebaseCrashlytics get _crashlytics =>
      _crashlyticsOverride ?? FirebaseCrashlytics.instance;

  void debug(String message) {
    if (kDebugMode) _logger.d(message);
  }

  void info(String message) {
    if (kDebugMode) _logger.i(message);
    if (kReleaseMode) _crashlytics.log(message);
  }

  void warn(String message, [Object? error, StackTrace? stack]) {
    if (kDebugMode) _logger.w(message, error: error, stackTrace: stack);
    if (kReleaseMode) {
      _crashlytics.log(message);
      if (error != null) {
        _crashlytics.recordError(error, stack);
      }
    }
  }

  void error(String message, [Object? error, StackTrace? stack]) {
    if (kDebugMode) _logger.e(message, error: error, stackTrace: stack);
    if (kReleaseMode) {
      _crashlytics.log(message);
      _crashlytics.recordError(error ?? message, stack);
    }
  }

  void fatal(Object error, StackTrace stack, {String? reason}) {
    if (kDebugMode) {
      _logger.e(reason ?? 'Fatal error', error: error, stackTrace: stack);
    }
    if (kReleaseMode) {
      _crashlytics.recordError(error, stack, reason: reason, fatal: true);
    }
  }
}

final loggerProvider = Provider<AppLogger>((ref) => AppLogger());
