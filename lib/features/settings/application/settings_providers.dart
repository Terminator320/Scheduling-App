import 'dart:async';

class SettingsSaveDebouncer {
  SettingsSaveDebouncer({
    this.delay = const Duration(milliseconds: 250),
    this.onError,
  });

  final Duration delay;
  final void Function(Object error, StackTrace stackTrace)? onError;
  Timer? _timer;

  void run(Future<void> Function() save) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      unawaited(
        Future<void>.sync(save).catchError((Object e, StackTrace st) {
          onError?.call(e, st);
        }),
      );
    });
  }

  void dispose() {
    _timer?.cancel();
  }
}
