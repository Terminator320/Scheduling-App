import 'dart:async';

/// Runs [op] and, if it throws, retries after each delay in [delays].
///
/// Total attempts = `delays.length + 1`. The exception from the final
/// attempt is rethrown so the caller can decide what to do (fall through,
/// surface a notice, etc.). Each retry attempt is logged via [onRetry] if
/// supplied — boot-time call sites use this to push warnings into
/// Crashlytics without coupling the helper to a specific logger.
///
/// Used by the splash + cold-start paths to ride out transient Firestore
/// outages instead of silently signing the user out.
Future<T> retryAsync<T>(
  Future<T> Function() op, {
  required List<Duration> delays,
  void Function(int attempt, Object error, StackTrace stack)? onRetry,
}) async {
  for (var attempt = 0; attempt <= delays.length; attempt++) {
    try {
      return await op();
    } catch (e, st) {
      if (attempt == delays.length) rethrow;
      onRetry?.call(attempt + 1, e, st);
      await Future<void>.delayed(delays[attempt]);
    }
  }
  // Unreachable: the loop above either returns or rethrows.
  throw StateError('retryAsync exited without returning or throwing.');
}
