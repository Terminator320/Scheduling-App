import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/retry.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/siri/domain/schedule_snapshot.dart';

/// Who the Siri snapshot is being built for: the signed-in user's role plus,
/// for an employee, the users-doc id `appointments.employeeIds` holds.
typedef SiriSnapshotIdentity = ({String role, String docId});

/// The signed-in active user's role + users-doc id, or null when signed-out or
/// inactive (which clears the snapshot). Mirrors `widgetEmployeeIdProvider`,
/// but keeps the role: admins hear the whole business, employees only their own
/// assigned visits.
final siriSnapshotIdentityProvider =
    FutureProvider.autoDispose<SiriSnapshotIdentity?>((ref) async {
      final doc = ref.watch(currentUserDocProvider).value ?? const {};
      final role = (doc['role'] ?? '').toString().trim();
      final status = (doc['status'] ?? '').toString().trim();
      if (status != 'active' || (role != 'employee' && role != 'admin')) {
        return null;
      }
      final uid = ref.watch(authUidProvider).value;
      if (uid == null) return null;
      // Retry the post-sign-in read: the ID-token/role bridge can lag sign-in,
      // so a transient `permission-denied` would otherwise resolve null and
      // wipe the snapshot. Mirrors the splash/sign-in reads.
      final repo = ref.watch(employeesRepositoryProvider);
      final match = await retryAsync(
        () => repo.findUserByUid(uid),
        delays: const [
          Duration(milliseconds: 500),
          Duration(milliseconds: 1500),
        ],
      );
      final docId = match?.id;
      if (docId == null) return null;
      return (role: role, docId: docId);
    });

/// The current Siri schedule snapshot, or `data(null)` when it should be wiped
/// (signed-out / inactive). Sign-out clears it for free through that null —
/// there is no explicit clear on the sign-out path.
final scheduleSnapshotProvider =
    Provider.autoDispose<AsyncValue<Map<String, dynamic>?>>((ref) {
      final identityAsync = ref.watch(siriSnapshotIdentityProvider);
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
