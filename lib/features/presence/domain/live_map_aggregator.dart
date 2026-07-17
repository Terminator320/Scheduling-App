import 'package:flutter/material.dart';

import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/presence/domain/models/presence_fix.dart';

/// Staleness window for a presence fix on the admin live map. Keep in sync
/// with PRESENCE_STALE_MINUTES in functions/travel_utils.js.
const presenceStaleAfter = Duration(minutes: 25);

/// Pure reducers joining raw presence fixes with the active staff roster for
/// the admin live-location map. Every function takes `now` explicitly so the
/// whole feature tests with a fixed clock.
class LiveMapAggregator {
  LiveMapAggregator._();

  /// Joins [fixes] with [users] by users-doc id. A fix with no matching user,
  /// or whose user isn't active (disabled/invited leftover doc), is dropped.
  /// Result sorted by name.
  static List<StaffMapPoint> join({
    required List<PresenceFix> fixes,
    required List<EmployeeRecord> users,
  }) {
    final byId = {for (final u in users) u.id: u};
    final points = <StaffMapPoint>[];
    for (final fix in fixes) {
      final user = byId[fix.userDocId];
      if (user == null || !user.isActive) continue;
      points.add(
        StaffMapPoint(
          userDocId: fix.userDocId,
          name: user.name,
          color: user.color,
          lat: fix.lat,
          lng: fix.lng,
          updatedAt: fix.updatedAt,
        ),
      );
    }
    points.sort((a, b) => a.name.compareTo(b.name));
    return points;
  }

  /// True strictly once [updatedAt] is older than [presenceStaleAfter]; null
  /// (a pending own-write's server timestamp) reads as fresh.
  static bool isStale(DateTime? updatedAt, DateTime now) {
    if (updatedAt == null) return false;
    return now.difference(updatedAt) > presenceStaleAfter;
  }

  /// Widget-facing freshness bucket so call sites only map to l10n strings.
  static FreshnessBucket freshnessOf(DateTime? updatedAt, DateTime now) {
    if (updatedAt == null) return const FreshnessJustNow();
    final elapsed = now.difference(updatedAt);
    if (elapsed < const Duration(minutes: 1)) return const FreshnessJustNow();
    if (elapsed < const Duration(minutes: 60)) {
      return FreshnessMinutesAgo(elapsed.inMinutes);
    }
    return FreshnessHoursAgo(elapsed.inHours);
  }
}

/// One staff member's plotted position, ready for the map widget.
class StaffMapPoint {
  const StaffMapPoint({
    required this.userDocId,
    required this.name,
    required this.color,
    required this.lat,
    required this.lng,
    required this.updatedAt,
  });

  final String userDocId;
  final String name;
  final Color color;
  final double lat;
  final double lng;
  final DateTime? updatedAt;
}

/// How long ago a fix was reported, bucketed for display.
sealed class FreshnessBucket {
  const FreshnessBucket();
}

class FreshnessJustNow extends FreshnessBucket {
  const FreshnessJustNow();
}

class FreshnessMinutesAgo extends FreshnessBucket {
  const FreshnessMinutesAgo(this.minutes);
  final int minutes;
}

class FreshnessHoursAgo extends FreshnessBucket {
  const FreshnessHoursAgo(this.hours);
  final int hours;
}
