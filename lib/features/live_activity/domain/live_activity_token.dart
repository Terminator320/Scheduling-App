/// Which APNs token a `users/{docId}/liveActivityTokens/{id}` row holds.
enum LiveActivityTokenKind {
  /// Device-wide iOS 17.2+ push-to-start token — lets the server CREATE the
  /// card on a closed, locked phone. One per device.
  pushToStart('pushToStart'),

  /// Per-activity update token — lets the server update or end ONE live card.
  /// One per activity, never one per device.
  update('update');

  const LiveActivityTokenKind(this.raw);

  /// The stored `kind` field value.
  final String raw;
}

/// How long a token row stays useful before server-side TTL prune (30 days for push-to-start device tokens, 1 day for per-activity update tokens).
const liveActivityPushToStartTtl = Duration(days: 30);
const liveActivityUpdateTtl = Duration(days: 1);

/// Doc id for a token row (push-to-start keys on token itself, update keys on activity id so token rotation replaces not duplicates).
String liveActivityTokenDocId({
  required LiveActivityTokenKind kind,
  required String token,
  String? activityId,
}) => switch (kind) {
  LiveActivityTokenKind.pushToStart => token,
  LiveActivityTokenKind.update => activityId ?? token,
};

/// Absolute expiry stamped on a token row, for the server-side TTL prune.
DateTime liveActivityTokenExpiry({
  required LiveActivityTokenKind kind,
  required DateTime now,
}) => switch (kind) {
  LiveActivityTokenKind.pushToStart => now.add(liveActivityPushToStartTtl),
  LiveActivityTokenKind.update => now.add(liveActivityUpdateTtl),
};
