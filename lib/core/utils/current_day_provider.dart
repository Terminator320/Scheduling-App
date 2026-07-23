import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/utils/date_utils_helper.dart';

/// Current local day, re-emitted at midnight so schedule mirrors rebuild their today/tomorrow buckets.
final currentDayProvider = Provider<DateTime>((ref) {
  final now = DateTime.now();
  final today = now.dateOnly;
  final nextMidnight = DateTime(today.year, today.month, today.day + 1);
  // One second past midnight so rebuild can't see 23:59:59.999.
  final timer = Timer(
    nextMidnight.difference(now) + const Duration(seconds: 1),
    ref.invalidateSelf,
  );
  ref.onDispose(timer.cancel);
  return today;
});
