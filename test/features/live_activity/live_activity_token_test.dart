import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/live_activity/domain/live_activity_token.dart';

void main() {
  final now = DateTime(2026, 7, 19, 8, 30);

  group('liveActivityTokenDocId', () {
    test('a push-to-start row keys on the device token', () {
      expect(
        liveActivityTokenDocId(
          kind: LiveActivityTokenKind.pushToStart,
          token: 'pts-token',
        ),
        'pts-token',
      );
    });

    test('an update row keys on its activity id, not the token', () {
      expect(
        liveActivityTokenDocId(
          kind: LiveActivityTokenKind.update,
          token: 'rotated-token',
          activityId: 'activity-1',
        ),
        'activity-1',
      );
    });

    test('a token rotation reuses the same update row', () {
      final first = liveActivityTokenDocId(
        kind: LiveActivityTokenKind.update,
        token: 'token-a',
        activityId: 'activity-1',
      );
      final second = liveActivityTokenDocId(
        kind: LiveActivityTokenKind.update,
        token: 'token-b',
        activityId: 'activity-1',
      );
      expect(first, second);
    });
  });

  group('liveActivityTokenExpiry', () {
    test('a push-to-start token outlives an update token', () {
      final pushToStart = liveActivityTokenExpiry(
        kind: LiveActivityTokenKind.pushToStart,
        now: now,
      );
      final update = liveActivityTokenExpiry(
        kind: LiveActivityTokenKind.update,
        now: now,
      );
      expect(pushToStart, now.add(liveActivityPushToStartTtl));
      expect(update, now.add(liveActivityUpdateTtl));
      expect(pushToStart.isAfter(update), isTrue);
    });
  });

  group('LiveActivityTokenKind', () {
    test('raw values match the stored `kind` field', () {
      expect(LiveActivityTokenKind.pushToStart.raw, 'pushToStart');
      expect(LiveActivityTokenKind.update.raw, 'update');
    });
  });
}
