import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// Thin clients-feature facade over the calendar-owned appointment history:
/// the history view pages and searches through these providers instead of
/// reaching into the calendar feature's data layer directly (it keeps only
/// the calendar *domain* import for the record type).
final historyPagerProvider = Provider<HistoryPager>(
  (ref) => HistoryPager(ref.watch(appointmentsRepositoryProvider)),
);

/// Cursor-paged (newest-first) reads over terminal appointments.
class HistoryPager {
  const HistoryPager(this._repo);

  final AppointmentsRepository _repo;

  Future<List<AppointmentRecord>> fetchPage({
    required int limit,
    AppointmentRecord? after,
  }) {
    return _repo.fetchHistoryPage(after: after, limit: limit);
  }
}

/// Database-backed history search: finds terminal appointments across the
/// whole history window, not just the pages loaded into the list. AutoDispose
/// so each distinct query instance is freed once no longer watched.
final historySearchProvider = FutureProvider.autoDispose
    .family<List<AppointmentRecord>, String>((
      ref,
      query,
    ) async {
      final repo = ref.watch(appointmentsRepositoryProvider);
      // Committed results must not outlive a local write: a deleted visit
      // would stay listed (and tappable) until this provider was disposed.
      final sub = repo.onLocalWrite.listen((_) => ref.invalidateSelf());
      ref.onDispose(sub.cancel);
      return repo.searchHistory(query);
    });

/// This client's appointments (most-recent first) for the client detail
/// "Job history" section. AutoDispose + family keyed by clientId so a closed
/// detail view frees the read; re-fetches on any local appointment write so an
/// edit made while the detail is open reflects immediately.
final clientJobHistoryProvider = FutureProvider.autoDispose
    .family<List<AppointmentRecord>, String>((ref, clientId) async {
      final repo = ref.watch(appointmentsRepositoryProvider);
      final sub = repo.onLocalWrite.listen((_) => ref.invalidateSelf());
      ref.onDispose(sub.cancel);
      return repo.fetchClientHistory(clientId: clientId);
    });
