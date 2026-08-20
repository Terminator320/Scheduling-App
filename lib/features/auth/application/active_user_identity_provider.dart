import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/core/utils/retry.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';

/// The signed-in user's role + users-doc id for schedule surfaces.
typedef ActiveUserIdentity = ({String role, String docId});

/// Resolves the signed-in active user's role and doc id, or null if they're
/// signed out or inactive. Also clears off-screen mirrors like the widget
/// and Siri snapshot.
final activeUserIdentityProvider =
    FutureProvider.autoDispose<ActiveUserIdentity?>((ref) async {
      // Await the settled value rather than branching on the AsyncValue: a
      // loading build that resolved the future itself then rebuilt on the
      // emission, so every sign-in paid for the uid lookup below twice.
      final doc = await ref.watch(currentUserDocProvider.future);
      final role = (doc['role'] ?? '').toString().trim();
      final status = (doc['status'] ?? '').toString().trim();
      if (status != 'active' || (role != 'employee' && role != 'admin')) {
        return null;
      }
      final uid = await ref.watch(authUidProvider.future);
      if (uid == null) return null;
      final repo = ref.watch(employeesRepositoryProvider);
      // We only got here because currentUserDocProvider emitted a populated
      // doc, so the stream behind it has already resolved this uid's doc id —
      // re-querying for it was a document read per emission plus one per cold
      // start, for something already in hand.
      final cachedId = repo.cachedUserDocId(uid);
      if (cachedId != null) return (role: role, docId: cachedId);

      // Retry this read right after sign-in — if we don't, ID-token/role
      // bridge lag can wipe the mirrors.
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
