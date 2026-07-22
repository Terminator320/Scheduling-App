import 'dart:async';

/// Reentrancy guard that coalesces — never drops — a concurrent re-sync.
///
/// The `main.dart`-driven registration controllers (push, presence, Live
/// Activity) all run an idempotent `sync()` on every account-doc emission and
/// on language change, and a second call landing mid-flight must not be lost
/// (a stale locale/doc would stick until the next emission). This mixin owns
/// that contract in one place so the three can't drift: while a body is in
/// flight, a second [runCoalesced] sets a pending flag and returns; when the
/// in-flight body finishes, it re-runs exactly once so the latest state wins.
/// Overlapping requests collapse to a single trailing re-run, never a queue.
///
/// The `body` must handle its own errors — each controller logs with its own
/// tag — but the guard's `finally` resets the busy flag even if `body` throws,
/// so a failure can never wedge the guard shut.
mixin ReentrantSync {
  bool _syncBusy = false;
  bool _syncPending = false;

  Future<void> runCoalesced(Future<void> Function() body) async {
    if (_syncBusy) {
      _syncPending = true;
      return;
    }
    _syncBusy = true;
    try {
      await body();
    } finally {
      _syncBusy = false;
      if (_syncPending) {
        _syncPending = false;
        unawaited(runCoalesced(body));
      }
    }
  }
}
