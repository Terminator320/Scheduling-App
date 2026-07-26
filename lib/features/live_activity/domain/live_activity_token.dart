/// Which APNs token a `users/{docId}/liveActivityTokens/{id}` row holds.
enum LiveActivityTokenKind {
  /// Device-wide iOS 17.2+ push-to-start token — lets the server CREATE the
  /// card on a closed, locked phone; one per device.
  pushToStart('pushToStart'),

  /// Per-activity update token — lets the server update or end ONE live card,
  /// one per activity (never one per device).
  update('update');

  const LiveActivityTokenKind(this.raw);

  /// The stored `kind` field value.
  final String raw;
}

/// How long a token row stays useful before the server's TTL prune kicks in
/// — 30 days for push-to-start device tokens, 1 day for per-activity update tokens.
const liveActivityPushToStartTtl = Duration(days: 30);
const liveActivityUpdateTtl = Duration(days: 1);

/// Doc id for a token row. Push-to-start keys on the token itself; update
/// keys on the activity id, so a token rotation replaces the row instead of duplicating it.
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
