import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/live_activity/domain/live_activity_token.dart';

/// I8: `liveActivityPushToStartTtl` (30 d) against the `liveActivityTokens`
/// rule's `expiresAt < request.time + duration.value(31, 'd')` was the one
/// Dart↔CEL hand-mirror in the repo with nothing reading the rules back —
/// `TextLimits`, `kSelfServiceUserFields`, `emergencyFieldNotSet`, the span
/// bound and the status allowlist all have one, precisely because Dart and CEL
/// cannot share a constant.
///
/// There is exactly ONE day of headroom, and the failure is silent in both
/// directions. Bump the Dart TTL and every push-to-start token write is
/// rejected — `LiveActivityRegistrationController` catches and logs with no
/// user-facing signal, so the symptom is "Live Activities quietly stopped
/// appearing on new devices". Lower the rules bound below the sweep's own TTL
/// and the same thing happens.
///
/// `live_activity_token_test.dart` covers `liveActivityTokenExpiry`, but it
/// restates the implementation with the same constant, so it holds for 30, 45
/// or 400 days and structurally cannot catch this.
void main() {
  late final rules = File('firestore.rules').readAsStringSync();

  /// The `duration.value(N, 'd')` ceiling the `liveActivityTokens` rule puts on
  /// a client-written `expiresAt`.
  int rulesExpiryBoundDays() {
    final block = RegExp(
      r'match /liveActivityTokens/\{activityId\} \{(.*?)\n      \}',
      dotAll: true,
    ).firstMatch(rules)?.group(1);
    expect(block, isNotNull, reason: 'the liveActivityTokens rule was removed');

    final bounds = RegExp(
      r"duration\.value\(\s*(\d+)\s*,\s*'d'\s*\)",
    ).allMatches(block!).map((m) => int.parse(m.group(1)!)).toList();
    expect(
      bounds,
      hasLength(1),
      reason: 'expected exactly one day-valued expiresAt bound',
    );
    return bounds.single;
  }

  test('the rule still BOUNDS expiresAt rather than only type-checking it', () {
    // A client-written TTL field bounded only by `is timestamp` lets a modified
    // client park a row past every server-side reaper.
    final block = RegExp(
      r'match /liveActivityTokens/\{activityId\} \{(.*?)\n      \}',
      dotAll: true,
    ).firstMatch(rules)!.group(1)!;
    final collapsed = block.replaceAll(RegExp(r'\s+'), ' ');
    expect(collapsed, contains('request.resource.data.expiresAt is timestamp'));
    expect(
      collapsed,
      contains('request.resource.data.expiresAt < request.time'),
    );
  });

  test('the push-to-start TTL fits under the rules bound', () {
    // The comparison in the rules is STRICT (`<`), so equality would be
    // rejected too — a 31-day Dart TTL against a 31-day bound fails every write.
    expect(
      liveActivityPushToStartTtl,
      lessThan(Duration(days: rulesExpiryBoundDays())),
      reason:
          'liveActivityPushToStartTtl is at or past the firestore.rules '
          'expiresAt ceiling — every push-to-start token write would be '
          'rejected, silently',
    );
  });

  test('the per-activity update TTL fits under the same bound', () {
    // Both kinds are written through `liveActivityTokenExpiry` into the same
    // collection, so the one rule governs both.
    expect(
      liveActivityUpdateTtl,
      lessThan(Duration(days: rulesExpiryBoundDays())),
      reason:
          'liveActivityUpdateTtl is at or past the firestore.rules expiresAt '
          'ceiling — every update-token write would be rejected, silently',
    );
  });

  test('the bound stays just above the longest TTL the app writes', () {
    // The other direction: a ceiling far above what the app writes stops being
    // a bound at all, and lets a modified client mint rows the sweep and the
    // TTL policy will honour for a month longer than anything legitimate.
    final longest = liveActivityPushToStartTtl > liveActivityUpdateTtl
        ? liveActivityPushToStartTtl
        : liveActivityUpdateTtl;
    expect(
      Duration(days: rulesExpiryBoundDays()) - longest,
      lessThanOrEqualTo(const Duration(days: 7)),
      reason:
          'the rules ceiling has drifted well past the longest TTL the app '
          'writes — raise both together, or not at all',
    );
  });
}
