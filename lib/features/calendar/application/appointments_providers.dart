import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

final appointmentsRepositoryProvider = Provider<AppointmentsRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final repository = FirebaseAppointmentsRepository(firestore);
  ref.onDispose(repository.dispose);
  return repository;
});

/// How long an unwatched month keeps its listener warm for reuse on page-back.
const _monthRangeKeepAlive = Duration(minutes: 3);

/// Keeps a provider alive after its watchers leave, enabling reuse on page-back.
///
/// Public because the dashboard's one-shot `.get()` halves need exactly the same
/// grace as the live half beside them: without it, leaving the dashboard and
/// coming straight back — drilling into a job from the Attention list and
/// pressing back is precisely that — tore down and re-issued up to ~2000
/// document reads, while the live stream cost nothing.
void keepWarmWithGrace(Ref ref) => _keepWarmWithGrace(ref);

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
      final uidState = ref.watch(authUidProvider);
      if (uidState.hasError) {
        return Stream.error(
          uidState.error!,
          uidState.stackTrace ?? StackTrace.current,
        );
      }
      if (uidState.isLoading) {
        return Stream.fromFuture(
          ref.watch(authUidProvider.future),
        ).asyncExpand((uid) {
          if (uid == null) return Stream.value(const <AppointmentRecord>[]);
          _keepWarmWithGrace(ref);
          return ref.watch(appointmentsRepositoryProvider).watchInRange(range);
        });
      }
      if (uidState.value == null) return Stream.value(const []);
      _keepWarmWithGrace(ref);
      return ref.watch(appointmentsRepositoryProvider).watchInRange(range);
    });

/// Family key for [myAppointmentsProvider]. Kept as a private typedef since
/// records are structurally typed anyway.
typedef _MyAppointmentsKey = ({String employeeId, AppointmentDateRange range});

final myAppointmentsProvider = StreamProvider.family
    .autoDispose<List<AppointmentRecord>, _MyAppointmentsKey>((ref, key) {
      final uidState = ref.watch(authUidProvider);
      if (uidState.hasError) {
        return Stream.error(
          uidState.error!,
          uidState.stackTrace ?? StackTrace.current,
        );
      }
      if (uidState.isLoading) {
        return Stream.fromFuture(
          ref.watch(authUidProvider.future),
        ).asyncExpand((uid) {
          if (uid == null) return Stream.value(const <AppointmentRecord>[]);
          _keepWarmWithGrace(ref);
          return ref
              .watch(appointmentsRepositoryProvider)
              .watchForEmployeeInRange(key.employeeId, key.range);
        });
      }
      if (uidState.value == null) return Stream.value(const []);
      // Same keep-alive grace as admin provider.
      _keepWarmWithGrace(ref);
      return ref
          .watch(appointmentsRepositoryProvider)
          .watchForEmployeeInRange(key.employeeId, key.range);
    });

/// The range stream's list, logging once under [tag] when the query failed.
///
/// A bare `.value ?? const []` made a rejected or broken listener
/// indistinguishable from a day with genuinely no work, AND unlogged — so a
/// roster row read "0 jobs today", the TODAY panel read empty and the
/// availability warning never fired, with nothing in Crashlytics. The reducers
/// that consume this deliberately still degrade to an empty list rather than
/// growing an error state: the surfaces are a count badge and two small panels,
/// and "no work" is the honest thing to paint while the failure is recorded.
/// A surface that must tell the two apart reads the `AsyncValue` itself, the
/// way `emergencyContactProvider`'s consumers do.
///
/// Called from a provider body, so it runs once per emission, not per rebuild.
List<AppointmentRecord> appointmentsOrEmpty(
  Ref ref,
  AsyncValue<List<AppointmentRecord>> appointments,
  String tag,
) {
  if (appointments.hasError) {
    ref
        .read(loggerProvider)
        .warn(tag, appointments.error, appointments.stackTrace);
  }
  return appointments.value ?? const [];
}
