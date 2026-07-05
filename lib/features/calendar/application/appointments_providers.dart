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

/// How long an unwatched month keeps its Firestore listener warm, so paging
/// back within this window reuses the stream instead of re-opening (and
/// re-reading) the same range query on every month swipe.
const _monthRangeKeepAlive = Duration(minutes: 3);

/// Holds an autoDispose provider's keep-alive link open for
/// [_monthRangeKeepAlive] after its last watcher leaves, so a quick page-back
/// reuses the warm listener instead of re-subscribing (and re-reading).
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

/// Family key for [myAppointmentsProvider]. Callers pass the record literal;
/// records are structural, so the alias stays library-private.
typedef _MyAppointmentsKey = ({String employeeId, AppointmentDateRange range});

final myAppointmentsProvider = StreamProvider.family
    .autoDispose<List<AppointmentRecord>, _MyAppointmentsKey>((ref, key) {
      if (ref.authUid == null) return Stream.value(const []);
      // Same keep-alive grace as the admin range provider: an employee paging
      // back within the window reuses the warm listener instead of re-reading.
      _keepWarmWithGrace(ref);
      return ref
          .watch(appointmentsRepositoryProvider)
          .watchForEmployeeInRange(key.employeeId, key.range);
    });
