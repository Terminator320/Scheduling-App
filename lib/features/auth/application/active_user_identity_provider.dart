import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/core/utils/retry.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';

/// The signed-in user's role + users-doc id for schedule surfaces.
typedef ActiveUserIdentity = ({String role, String docId});

/// Signed-in active user's role + doc id, or null signed-out/inactive; clears off-screen mirrors (widget, Siri snapshot).
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
      // Retry post-sign-in read; ID-token/role bridge lag would wipe mirrors.
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
