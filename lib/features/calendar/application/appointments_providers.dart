import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

final appointmentsRepositoryProvider = Provider<AppointmentsRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return FirebaseAppointmentsRepository(firestore);
});

/// How long an unwatched month keeps its listener warm for reuse on page-back.
const _monthRangeKeepAlive = Duration(minutes: 3);

/// Keeps a listener alive after watchers leave, enabling reuse on page-back.
void _keepWarmWithGrace(Ref ref) {
  final link = ref.keepAlive();
  Timer? evictTimer;
  ref
    ..onCancel(() => evictTimer = Timer(_monthRangeKeepAlive, link.close))
    ..onResume(() => evictTimer?.cancel())
    ..onDispose(() => evictTimer?.cancel());
}

final appointmentsInRangeProvider = StreamProvider.family
    .autoDispose<List<AppointmentRecord>, AppointmentDateRange>((ref, range) {
      if (ref.authUid == null) return Stream.value(const []);
      _keepWarmWithGrace(ref);
      return ref.watch(appointmentsRepositoryProvider).watchInRange(range);
    });

/// Family key for [myAppointmentsProvider]. Kept as a private typedef since
/// records are structurally typed anyway.
typedef _MyAppointmentsKey = ({String employeeId, AppointmentDateRange range});

final myAppointmentsProvider = StreamProvider.family
    .autoDispose<List<AppointmentRecord>, _MyAppointmentsKey>((ref, key) {
      if (ref.authUid == null) return Stream.value(const []);
      // Same keep-alive grace as admin provider.
      _keepWarmWithGrace(ref);
      return ref
          .watch(appointmentsRepositoryProvider)
          .watchForEmployeeInRange(key.employeeId, key.range);
    });
