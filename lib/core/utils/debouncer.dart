import 'dart:async';

/// How long a search field waits after the last keystroke before it reads.
///
/// One owner because it is one cost dial, not a per-surface taste: every
/// debounced search in the app spends the same bounded window on the same
/// collections. It was written out at four call sites and had already split
/// two ways (300 ms on the two appointment sheets, 250 ms on Clients and
/// History), which is the drift this constant ends.
///
/// It lives here rather than on `ClientSearchPolicy` because the callers span
/// features — the appointment sheets debounce a CLIENT search, but History
/// debounces an APPOINTMENT one, and a cross-feature constant parked in one
/// feature's policy is the import this file exists to make unnecessary.
const Duration kSearchDebounce = Duration(milliseconds: 250);

/// Coalesces rapid calls into one, firing only the last action within
/// [duration] (e.g. per-keystroke search). Own one instance per widget state.
class Debouncer {
  Debouncer(this.duration, {this.onError});

  final Duration duration;
  final void Function(Object error, StackTrace stackTrace)? onError;
  Timer? _timer;

  void run(FutureOr<void> Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      _timer = null;
      Future.sync(action).catchError((Object error, StackTrace stackTrace) {
        onError?.call(error, stackTrace);
      });
    });
  }

  /// Drops any pending action without running it.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}
