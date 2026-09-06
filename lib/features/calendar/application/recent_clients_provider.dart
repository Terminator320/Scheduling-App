import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/recent_client.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';

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
  // Projected down to the role STRING, as `employeesProvider` does: a `Map`
  // compares by identity, so watching the raw doc re-ran the 60-doc query on
  // any own-doc write.
  final role = await ref.watch(
    currentUserDocProvider.selectAsync(
      (doc) => (doc['role'] ?? '').toString().trim(),
    ),
  );
  if (role != 'admin') return const [];
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

/// The real client behind a recents row.
///
/// A [RecentClient] carries only what an appointment denormalizes, so
/// attaching one as-is gave the booking form a client with no address — where
/// the SAME client picked from search pre-fills one and offers the switch.
/// Answers null on any failure; the caller falls back to the denormalized
/// fields, which is still better than refusing the tap.
Future<ClientRecord?> resolveRecentClient(WidgetRef ref, RecentClient recent) {
  final logger = ref.read(loggerProvider);
  return ref
      .read(clientsRepositoryProvider)
      .getClientById(recent.clientId)
      .catchError((Object e, StackTrace st) {
        logger.warn('CLI-RECENT resolve failed', e, st);
        return null;
      });
}
