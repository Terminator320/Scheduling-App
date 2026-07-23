import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// Facade over calendar-owned appointment history; keeps only calendar domain import for record type.
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

/// Database-backed history search across whole window; autoDispose frees each query instance when unwatched.
final historySearchProvider = FutureProvider.autoDispose
    .family<List<AppointmentRecord>, String>((
      ref,
      query,
    ) async {
      final repo = ref.watch(appointmentsRepositoryProvider);
      // Invalidate on local write so deleted visits don't linger in cached results.
      final sub = repo.onLocalWrite.listen((_) => ref.invalidateSelf());
      ref.onDispose(sub.cancel);
      return repo.searchHistory(query);
    });

/// Client appointments for Job history section; autoDispose keyed by clientId, re-fetches on local write.
final clientJobHistoryProvider = FutureProvider.autoDispose
    .family<List<AppointmentRecord>, String>((ref, clientId) async {
      final repo = ref.watch(appointmentsRepositoryProvider);
      final sub = repo.onLocalWrite.listen((_) => ref.invalidateSelf());
      ref.onDispose(sub.cancel);
      return repo.fetchClientHistory(clientId: clientId);
    });
