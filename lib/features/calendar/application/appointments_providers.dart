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
      ref.keepAlive();
      if (ref.authUid == null) return Stream.value(const []);
      return ref.watch(appointmentsRepositoryProvider).watchInRange(range);
    });

typedef MyAppointmentsKey = ({String employeeId, AppointmentDateRange range});

final myAppointmentsProvider = StreamProvider.family
    .autoDispose<List<AppointmentRecord>, MyAppointmentsKey>((ref, key) {
      ref.keepAlive();
      if (ref.authUid == null) return Stream.value(const []);
      return ref
          .watch(appointmentsRepositoryProvider)
          .watchForEmployeeInRange(key.employeeId, key.range);
    });

final appointmentHistoryProvider = StreamProvider<List<AppointmentRecord>>((
  ref,
) {
  if (ref.authUid == null) return Stream.value(const []);
  return ref.watch(appointmentsRepositoryProvider).watchHistory();
});

final appointmentByIdProvider = FutureProvider.family
    .autoDispose<AppointmentRecord?, String>((ref, id) {
      final repo = ref.watch(appointmentsRepositoryProvider);
      return repo.getAppointmentById(id);
    });
