import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

final appointmentsRepositoryProvider = Provider<AppointmentsRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return FirebaseAppointmentsRepository(firestore);
});

final appointmentsInRangeProvider = StreamProvider.family
    .autoDispose<List<AppointmentRecord>, AppointmentDateRange>((ref, range) {
      if (ref.authUid == null) return Stream.value(const []);
      return ref.watch(appointmentsRepositoryProvider).watchInRange(range);
    });

typedef MyAppointmentsKey = ({String employeeId, AppointmentDateRange range});

final myAppointmentsProvider = StreamProvider.family
    .autoDispose<List<AppointmentRecord>, MyAppointmentsKey>((ref, key) {
      if (ref.authUid == null) return Stream.value(const []);
      return ref
          .watch(appointmentsRepositoryProvider)
          .watchForEmployeeInRange(key.employeeId, key.range);
    });

/// Database-backed history search: finds terminal appointments across the whole
/// history window, not just the pages loaded into the list. AutoDispose so each
/// distinct query instance is freed once no longer watched.
final historySearchProvider = FutureProvider.autoDispose
    .family<List<AppointmentRecord>, String>((
      ref,
      query,
    ) async {
      final repo = ref.watch(appointmentsRepositoryProvider);
      return repo.searchHistory(query);
    });
