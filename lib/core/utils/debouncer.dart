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
  /// [onError] is REQUIRED: the action runs from a timer callback, so a throw
  /// inside it has no caller left to catch it. It was optional once and five
  /// of the six call sites omitted it, which turned every failed debounced
  /// search into silence — nothing logged, nothing in Crashlytics, the search
  /// just returning nothing. Requiring it is what makes that omission
  /// impossible at a NEW call site. Build it from a logger read BEFORE the
  /// widget can unmount (assign in `initState`, never a lazy `late final`
  /// touching `ref`) — the handler can fire after dispose, and `ref.read` on
  /// an unmounted consumer throws under Riverpod 3.
  Debouncer(this.duration, {required this.onError});

  final Duration duration;
  final void Function(Object error, StackTrace stackTrace) onError;
  Timer? _timer;

  void run(FutureOr<void> Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      _timer = null;
      Future.sync(action).catchError(onError);
    });
  }

  /// Drops any pending action without running it.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}
