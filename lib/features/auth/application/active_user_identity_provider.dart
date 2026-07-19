import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/core/utils/retry.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';

/// Who the signed-in user is to the schedule surfaces: their role plus the
/// users-doc id `appointments.employeeIds` holds.
typedef ActiveUserIdentity = ({String role, String docId});

/// The signed-in active user's role + users-doc id, or null when signed-out or
/// inactive — which is how every off-screen schedule mirror (iOS widget, Siri
/// snapshot) clears itself without an explicit sign-out hook.
///
/// Both employees **and admins** qualify: admins can assign themselves to jobs,
/// so their own schedule is a real thing to mirror. Consumers that need the
/// business-wide view instead branch on the record's `role`.
final activeUserIdentityProvider =
    FutureProvider.autoDispose<ActiveUserIdentity?>((ref) async {
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
      // wipe the mirrors. Mirrors the splash/sign-in reads.
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
