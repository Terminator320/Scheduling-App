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

/// How long a token row stays useful before the server's TTL prune may drop
/// it. A push-to-start token is device-scoped and re-upserted on every sync,
/// so it gets a long window; an update token belongs to a card that lives
/// hours at most, so a stale one is dead weight after a day.
const liveActivityPushToStartTtl = Duration(days: 30);
const liveActivityUpdateTtl = Duration(days: 1);

/// Doc id for a token row. A push-to-start token has no activity, so it keys
/// on the token itself (the `fcmTokens` token-as-doc-id shape, naturally
/// unique per device); an update token keys on its activity id so an iOS
/// token rotation replaces that card's row instead of duplicating it.
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
