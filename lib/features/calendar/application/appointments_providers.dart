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

final appointmentsInRangeProvider = StreamProvider.family
    .autoDispose<List<AppointmentRecord>, AppointmentDateRange>((ref, range) {
      if (ref.authUid == null) return Stream.value(const []);
      final link = ref.keepAlive();
      Timer? evictTimer;
      ref
        ..onCancel(() {
          // Last watcher gone: close the keep-alive link after a grace period
          // so a quick page-back doesn't re-subscribe.
          evictTimer = Timer(_monthRangeKeepAlive, link.close);
        })
        ..onResume(() => evictTimer?.cancel())
        ..onDispose(() => evictTimer?.cancel());
      return ref.watch(appointmentsRepositoryProvider).watchInRange(range);
    });

/// Family key for [myAppointmentsProvider]. Callers pass the record literal;
/// records are structural, so the alias stays library-private.
typedef _MyAppointmentsKey = ({String employeeId, AppointmentDateRange range});

final myAppointmentsProvider = StreamProvider.family
    .autoDispose<List<AppointmentRecord>, _MyAppointmentsKey>((ref, key) {
      if (ref.authUid == null) return Stream.value(const []);
      return ref
          .watch(appointmentsRepositoryProvider)
          .watchForEmployeeInRange(key.employeeId, key.range);
    });
