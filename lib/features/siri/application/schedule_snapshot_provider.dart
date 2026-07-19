import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/auth/application/active_user_identity_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/siri/domain/schedule_snapshot.dart';

/// The current Siri schedule snapshot, or `data(null)` when it should be wiped
/// (signed-out / inactive). Sign-out clears it for free through that null —
/// there is no explicit clear on the sign-out path. Admins hear the whole
/// business, employees only their own assigned visits.
final scheduleSnapshotProvider =
    Provider.autoDispose<AsyncValue<Map<String, dynamic>?>>((ref) {
      final identityAsync = ref.watch(activeUserIdentityProvider);
      if (identityAsync.isLoading) return const AsyncValue.loading();
      final identity = identityAsync.value;
      if (identity == null) {
        return const AsyncValue<Map<String, dynamic>?>.data(null);
      }
      final now = DateTime.now();
      final startOfToday = now.dateOnly;
      final range = AppointmentDateRange(
        start: startOfToday,
        end: DateTime(
          startOfToday.year,
          startOfToday.month,
          startOfToday.day + scheduleSnapshotLookaheadDays + 1,
        ),
      );
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
        ),
      );
    });
