import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// A thin facade over calendar-owned appointment history, so this file only needs
/// the calendar domain import for the record type.
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

/// Database-backed history search across the whole window. It's autoDispose, so each
/// query instance gets freed once nothing's watching it anymore.
final historySearchProvider = FutureProvider.autoDispose
    .family<List<AppointmentRecord>, String>((
      ref,
      query,
    ) async {
      final repo = ref.watch(appointmentsRepositoryProvider);
      // Invalidate on local write so deleted visits don't linger in cached results.
      final sub = repo.onLocalWrite.listen(
        (_) => ref.invalidateSelf(),
        onError: (Object e, StackTrace st) => ref
            .read(loggerProvider)
            .warn('HIST-SEARCH invalidate error', e, st),
      );
      ref.onDispose(sub.cancel);
      return repo.searchHistory(query);
    });

/// Client appointments for the Job history section. AutoDispose, keyed by clientId,
/// and re-fetches whenever there's a local write.
final clientJobHistoryProvider = FutureProvider.autoDispose
    .family<List<AppointmentRecord>, String>((ref, clientId) async {
      final repo = ref.watch(appointmentsRepositoryProvider);
      final sub = repo.onLocalWrite.listen(
        (_) => ref.invalidateSelf(),
        onError: (Object e, StackTrace st) =>
            ref.read(loggerProvider).warn('HIST-LOAD invalidate error', e, st),
      );
      ref.onDispose(sub.cancel);
      return repo.fetchClientHistory(clientId: clientId);
    });
