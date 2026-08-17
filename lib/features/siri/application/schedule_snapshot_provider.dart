import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/utils/current_day_provider.dart';
import 'package:scheduling/features/auth/application/active_user_identity_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/siri/domain/schedule_snapshot.dart';

/// The current Siri schedule snapshot, or null when signed out. Admins see
/// all appointments; employees only see their own.
final scheduleSnapshotProvider =
    Provider.autoDispose<AsyncValue<Map<String, dynamic>?>>((ref) {
      final identityAsync = ref.watch(activeUserIdentityProvider);
      if (identityAsync.isLoading) return const AsyncValue.loading();
      // An identity read that FAILED is propagated as an error, never collapsed
      // into a settled null: null means "signed out, clear the snapshot", and a
      // Firestore failure is not that — Siri would answer "no appointments" to
      // someone who has jobs. See `AppSyncListeners._isUnsettled`.
      if (identityAsync.hasError) {
        return AsyncValue<Map<String, dynamic>?>.error(
          identityAsync.error!,
          identityAsync.stackTrace ?? StackTrace.current,
        );
      }
      final identity = identityAsync.value;
      if (identity == null) {
        return const AsyncValue<Map<String, dynamic>?>.data(null);
      }
      // Rebuilds this snapshot when the calendar day rolls over, so an app
      // left running overnight can't keep publishing yesterday's day buckets.
      final startOfToday = ref.watch(currentDayProvider);
      // The shared mirror window — the home widget asks for the same value, so
      // for an employee the two mirrors share ONE listener instead of opening
      // two whose windows nest.
      final range = AppointmentDateRange.forMirrors(startOfToday);
      final appts = identity.role == 'admin'
          ? ref.watch(appointmentsInRangeProvider(range))
          : ref.watch(
              myAppointmentsProvider((
                employeeId: identity.docId,
                range: range,
              )),
            );
      return appts.whenData(
        (list) => buildScheduleSnapshot(
          appointments: list,
          role: identity.role,
          now: DateTime.now(),
          viewerDocId: identity.docId,
        ),
      );
    });
