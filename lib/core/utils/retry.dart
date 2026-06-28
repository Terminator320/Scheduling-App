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

/// Stream sibling of [retryAsync]: re-subscribes to [create] when it errors and
/// [retryWhen] accepts the error, once per entry in [delays]. Used to survive
/// the post-sign-in `permission-denied` race on Firestore listeners — the ID
/// token / role bridge can lag behind sign-in, so the first subscription errors
/// even though the user is authorized; a retry after a short delay succeeds.
///
/// Errors [retryWhen] rejects (or that survive every retry) propagate to the
/// listener; normal completion ends the stream. [retryWhen] is a predicate so
/// this stays free of any Firebase import (the caller supplies the match).
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
      // `await for` (unlike `yield*`) surfaces the inner stream's errors as
      // exceptions in this body, so the retry catch below can see them.
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
