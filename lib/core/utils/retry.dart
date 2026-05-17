import 'dart:async';

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
  throw StateError('retryAsync exited without returning or throwing.');
}
