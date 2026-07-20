import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/utils/date_utils_helper.dart';

/// The current local calendar day, re-emitted when the day rolls over.
///
/// The off-screen schedule mirrors (iOS home-screen widget, Siri snapshot)
/// bucket appointments into "today" / "tomorrow" at build time. Their streams
/// only re-emit on an appointment write, so an app left resident overnight
/// would keep publishing yesterday's buckets — Siri answering "no appointments
/// today" while jobs exist. Watching this provider gives them a rebuild the
/// moment the date changes.
///
/// A timer that expires while the app is suspended fires once the isolate
/// resumes, so this covers both the resident-overnight and the
/// suspended-across-midnight cases.
final currentDayProvider = Provider<DateTime>((ref) {
  final now = DateTime.now();
  final today = now.dateOnly;
  final nextMidnight = DateTime(today.year, today.month, today.day + 1);
  // One second past the boundary so the rebuild can't observe 23:59:59.999.
  final timer = Timer(
    nextMidnight.difference(now) + const Duration(seconds: 1),
    ref.invalidateSelf,
  );
  ref.onDispose(timer.cancel);
  return today;
});
