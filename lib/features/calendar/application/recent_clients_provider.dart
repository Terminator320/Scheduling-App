import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/recent_client.dart';

/// Clients this admin booked recently, resolved once per session.
///
/// NOT autoDispose: it is read by a sheet that opens and closes many times a
/// day, and the whole point is that reopening costs nothing.
///
/// Empty for a non-admin. The underlying query has no `employeeIds` constraint
/// — employees may only read appointments they are assigned to — and adding one
/// would need a new composite index for no real gain, since an employee's
/// workflow here is to type the number anyway.
final recentClientsProvider = FutureProvider<List<RecentClient>>((ref) async {
  final doc = await ref.watch(currentUserDocProvider.future);
  if ((doc['role'] ?? '').toString().trim() != 'admin') return const [];
  final logger = ref.read(loggerProvider);
  final repo = ref.read(appointmentsRepositoryProvider);
  try {
    final bookings = await repo.fetchRecentClientBookings(limit: 60);
    return recentClientsFrom(bookings);
  } catch (e, st) {
    // Recents are a convenience; a failure must never block the picker.
    logger.warn('CLI-RECENT recent clients lookup failed', e, st);
    return const [];
  }
});
