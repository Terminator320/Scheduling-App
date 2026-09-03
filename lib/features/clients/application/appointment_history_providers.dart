import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// A thin facade over calendar-owned appointment history, so this file only
/// needs the calendar domain import for the record type.
final historyPagerProvider = Provider<HistoryPager>(
  (ref) => HistoryPager(ref.watch(appointmentsRepositoryProvider)),
);

/// Cursor-paged (newest-first) reads over terminal appointments.
class HistoryPager {
  const HistoryPager(this._repo);

  final AppointmentsRepository _repo;

  /// [employeeId] scopes the page to one assignee's jobs; null is the
  /// business-wide archive.
  Future<List<AppointmentRecord>> fetchPage({
    required int limit,
    AppointmentRecord? after,
    String? employeeId,
  }) {
    return _repo.fetchHistoryPage(
      after: after,
      limit: limit,
      employeeId: employeeId,
    );
  }
}

/// One history search: the words, and whose history.
typedef HistorySearchKey = ({String query, String? employeeId});

/// Database-backed history search across the whole window.
final historySearchProvider = FutureProvider.autoDispose
    .family<List<AppointmentRecord>, HistorySearchKey>((
      ref,
      key,
    ) async {
      final repo = ref.watch(appointmentsRepositoryProvider);
      // Resolved HERE, not inside the callback: this is autoDispose, so the
      // `Ref` is gone the moment the last listener does, and Riverpod 3's
      // `ref.read` THROWS on a disposed one.
      final logger = ref.read(loggerProvider);
      // Invalidate on local write so deleted visits don't linger in cached results.
      final sub = repo.onLocalWrite.listen(
        (_) => ref.invalidateSelf(),
        onError: (Object e, StackTrace st) =>
            logger.warn('HIST-SEARCH invalidate error', e, st),
      );
      ref.onDispose(sub.cancel);
      return repo.searchHistory(key.query, employeeId: key.employeeId);
    });

/// Client appointments for the Job history section.
final clientJobHistoryProvider = FutureProvider.autoDispose
    .family<List<AppointmentRecord>, String>((ref, clientId) async {
      final repo = ref.watch(appointmentsRepositoryProvider);
      // Hoisted for the same reason as `historySearchProvider` above.
      final logger = ref.read(loggerProvider);
      final sub = repo.onLocalWrite.listen(
        (_) => ref.invalidateSelf(),
        onError: (Object e, StackTrace st) =>
            logger.warn('HIST-LOAD invalidate error', e, st),
      );
      ref.onDispose(sub.cancel);
      return repo.fetchClientHistory(clientId: clientId);
    });
