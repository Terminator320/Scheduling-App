import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/utils/reentrant_sync.dart';

/// Minimal host that drives [ReentrantSync] with a body whose completion this
/// test controls, so overlap is deterministic (no reliance on wall-clock).
class _Host with ReentrantSync {
  int started = 0;
  final List<Completer<void>> _gates = <Completer<void>>[];

  Future<void> sync() => runCoalesced(_body);

  Future<void> _body() {
    started++;
    final gate = Completer<void>();
    _gates.add(gate);
    return gate.future;
  }

  /// Completes the oldest in-flight body, letting that run finish.
  void release() => _gates.removeAt(0).complete();
}

void main() {
  group('ReentrantSync.runCoalesced', () {
    test('runs the body when idle', () async {
      final host = _Host();
      final f = host.sync();
      expect(host.started, 1);
      host.release();
      await f;
    });

    test(
      'a call arriving mid-flight coalesces into a single trailing re-run',
      () async {
        final host = _Host();
        final first = host.sync();
        expect(host.started, 1);

        // Three concurrent calls while the first body is still in flight.
        unawaited(host.sync());
        unawaited(host.sync());
        unawaited(host.sync());
        // None started yet — they were folded into one pending flag.
        expect(host.started, 1);

        host.release(); // finish the first body
        await first;
        await Future<void>.delayed(
          Duration.zero,
        ); // let the trailing re-run start

        // Exactly ONE trailing run, not three.
        expect(host.started, 2);

        host.release(); // finish the trailing run
        await Future<void>.delayed(Duration.zero);
        // No further runs were queued.
        expect(host.started, 2);
      },
    );

    test('sequential (non-overlapping) calls each run', () async {
      final host = _Host();
      final a = host.sync();
      host.release();
      await a;

      final b = host.sync();
      expect(host.started, 2);
      host.release();
      await b;
    });

    test('a throwing body still resets the guard (no wedge)', () async {
      final host = _ThrowingHost();
      await host.sync(); // first body throws, swallowed by the host
      expect(host.started, 1);
      // The guard is not stuck busy — a later call runs.
      await host.sync();
      expect(host.started, 2);
    });
  });
}

/// Host whose body throws (swallowed the way real controllers do), to prove
/// the guard's `finally` clears busy even on failure.
class _ThrowingHost with ReentrantSync {
  int started = 0;

  Future<void> sync() => runCoalesced(_body);

  Future<void> _body() async {
    started++;
    try {
      throw StateError('boom');
    } catch (_) {
      // Controllers log with their own tag; here we just swallow.
    }
  }
}
