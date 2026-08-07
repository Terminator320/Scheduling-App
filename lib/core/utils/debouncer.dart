import 'dart:async';

/// Coalesces rapid calls into one, firing only the last action within
/// [duration] (e.g. per-keystroke search). Own one instance per widget state.
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
