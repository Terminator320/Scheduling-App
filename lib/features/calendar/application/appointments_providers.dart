import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

final appointmentsRepositoryProvider = Provider<AppointmentsRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return FirebaseAppointmentsRepository(firestore);
});

/// Streams appointments for a specific date range. Family-keyed by the range
/// so the calendar can re-watch when the focused month changes without
/// re-creating subscriptions for ranges that are still in scope.
///
/// `keepAlive` ensures that opening a sheet and returning doesn't tear down
/// the listener (perf #12). The provider is otherwise auto-disposed.
final appointmentsInRangeProvider =
    StreamProvider.family.autoDispose<List<AppointmentRecord>, AppointmentDateRange>(
      (ref, range) {
        ref.keepAlive();
        final repo = ref.watch(appointmentsRepositoryProvider);
        return repo.watchInRange(range);
      },
    );

/// Streams the history view (`status in {done, cancelled}`).
final appointmentHistoryProvider = StreamProvider<List<AppointmentRecord>>((
  ref,
) {
  final repo = ref.watch(appointmentsRepositoryProvider);
  return repo.watchHistory();
});

/// Single-shot fetch by id. Used by the photo-upload notice action so we
/// can navigate to the affected appointment after a background failure.
final appointmentByIdProvider =
    FutureProvider.family.autoDispose<AppointmentRecord?, String>(
      (ref, id) {
        final repo = ref.watch(appointmentsRepositoryProvider);
        return repo.getAppointmentById(id);
      },
    );
