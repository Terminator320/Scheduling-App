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

/// Stream sibling of [retryAsync]: re-subscribes on errors accepted by [retryWhen], surviving the post-sign-in permission-denied race.
Stream<T> retryStream<T>(
  Stream<T> Function() create, {
  required bool Function(Object error) retryWhen,
  List<Duration> delays = const [
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
    Duration(milliseconds: 2500),
  ],
  void Function(int attempt, Object error, StackTrace stack)? onRetry,
}) async* {
  for (var attempt = 0; ; attempt++) {
    try {
      // `await for` surfaces errors as exceptions so the retry catch can see them.
      await for (final value in create()) {
        yield value;
      }
      return;
    } catch (e, st) {
      if (!retryWhen(e) || attempt == delays.length) rethrow;
      onRetry?.call(attempt + 1, e, st);
      await Future<void>.delayed(delays[attempt]);
    }
  }
}
