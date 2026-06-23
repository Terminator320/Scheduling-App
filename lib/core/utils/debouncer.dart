import 'dart:async';

/// Coalesces rapid calls into one. Each [run] restarts the timer, so only the
/// last action scheduled within [duration] fires. Used to keep per-keystroke
/// search from firing a request on every character.
///
/// Own one per widget state and [dispose] it in `dispose()` to drop a pending
/// tick after the widget is gone.
class Debouncer {
  Debouncer(this.duration);

  final Duration duration;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// Drops any pending action without running it.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}
