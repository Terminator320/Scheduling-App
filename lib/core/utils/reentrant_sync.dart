import 'dart:async';

/// Reentrancy guard that coalesces concurrent calls, so the latest state
/// always wins. `body` is responsible for handling its own errors.
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
