import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/presence/application/presence_sync_controller.dart';

// Pure throttle/heartbeat/trailing-flush math on DateTime — no mocking needed.
// shouldTrackPresence is intentionally NOT re-tested here; it is fully covered
// by presence_sync_gates_test.dart.
void main() {
  final now = DateTime(2026, 7, 26, 9);

  group('shouldWritePresenceFix', () {
    test('null lastUpload always allows the first fix', () {
      expect(shouldWritePresenceFix(lastUploadAt: null, now: now), isTrue);
    });

    test('a fix at the same instant is throttled', () {
      expect(shouldWritePresenceFix(lastUploadAt: now, now: now), isFalse);
    });

    test('inside the 2-min gap is throttled', () {
      for (final elapsed in const [
        Duration(seconds: 1),
        Duration(minutes: 1),
        Duration(minutes: 1, seconds: 59),
        Duration(minutes: 1, milliseconds: 59999),
      ]) {
        expect(
          shouldWritePresenceFix(
            lastUploadAt: now.subtract(elapsed),
            now: now,
          ),
          isFalse,
          reason: 'elapsed $elapsed should throttle',
        );
      }
    });

    test('exactly at and past the gap allows the fix', () {
      expect(
        shouldWritePresenceFix(
          lastUploadAt: now.subtract(minPresenceUploadGap),
          now: now,
        ),
        isTrue,
      );
      for (final elapsed in const [
        Duration(minutes: 2, seconds: 1),
        Duration(minutes: 5),
        Duration(hours: 1),
      ]) {
        expect(
          shouldWritePresenceFix(
            lastUploadAt: now.subtract(elapsed),
            now: now,
          ),
          isTrue,
          reason: 'elapsed $elapsed should allow',
        );
      }
    });
  });

  group('shouldHeartbeat', () {
    test('never fires before any upload happened', () {
      expect(shouldHeartbeat(lastUploadAt: null, now: now), isFalse);
    });

    test('does not fire inside the heartbeat period', () {
      for (final elapsed in const [
        Duration.zero,
        Duration(minutes: 5),
        Duration(minutes: 9, seconds: 59),
      ]) {
        expect(
          shouldHeartbeat(
            lastUploadAt: now.subtract(elapsed),
            now: now,
          ),
          isFalse,
          reason: 'elapsed $elapsed should not heartbeat',
        );
      }
    });

    test('fires exactly at and past the heartbeat period', () {
      expect(
        shouldHeartbeat(
          lastUploadAt: now.subtract(presenceHeartbeatEvery),
          now: now,
        ),
        isTrue,
      );
      for (final elapsed in const [
        Duration(minutes: 10, seconds: 1),
        Duration(minutes: 30),
      ]) {
        expect(
          shouldHeartbeat(
            lastUploadAt: now.subtract(elapsed),
            now: now,
          ),
          isTrue,
          reason: 'elapsed $elapsed should heartbeat',
        );
      }
    });
  });

  group('trailingFlushDelay', () {
    test('returns null when a write is already allowed', () {
      // null lastUpload, exactly at the gap, and past the gap all allow now.
      expect(trailingFlushDelay(lastUploadAt: null, now: now), isNull);
      expect(
        trailingFlushDelay(
          lastUploadAt: now.subtract(minPresenceUploadGap),
          now: now,
        ),
        isNull,
      );
      expect(
        trailingFlushDelay(
          lastUploadAt: now.subtract(const Duration(minutes: 3)),
          now: now,
        ),
        isNull,
      );
    });

    test('returns the remaining wait (gap - elapsed) when throttled', () {
      for (final elapsed in const [
        Duration.zero,
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 1, seconds: 59),
      ]) {
        expect(
          trailingFlushDelay(
            lastUploadAt: now.subtract(elapsed),
            now: now,
          ),
          minPresenceUploadGap - elapsed,
          reason: 'elapsed $elapsed remaining should be gap - elapsed',
        );
      }
    });

    test('a fresh fix (zero elapsed) waits the full gap', () {
      expect(
        trailingFlushDelay(lastUploadAt: now, now: now),
        minPresenceUploadGap,
      );
    });

    test('one second before the gap waits one second', () {
      expect(
        trailingFlushDelay(
          lastUploadAt: now.subtract(const Duration(minutes: 1, seconds: 59)),
          now: now,
        ),
        const Duration(seconds: 1),
      );
    });
  });
}
