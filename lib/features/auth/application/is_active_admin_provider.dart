import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/auth/application/account_status_provider.dart';

/// True only while the LIVE Firestore user doc says this session is an active
/// admin.
///
/// Every admin-gated surface reached by a PUSHED route takes its `isAdmin` from
/// a route argument, which is a snapshot: a stale back stack, an argless push
/// or a deep link can all carry one that no longer describes the signed-in
/// person. This is the same question asked of Firestore, which is the standing
/// rule for anything that gates access.
///
/// Fails CLOSED while the doc is unsettled, matching the least-privilege
/// default every appointment surface already takes. There is no loading window
/// in practice: `currentUserDocProvider` is a non-autoDispose stream the app
/// shell already holds open, so a pushed screen reads a settled value on its
/// first build.
final isActiveAdminProvider = Provider<bool>((ref) {
  final doc = ref.watch(currentUserDocProvider).value;
  if (doc == null) return false;
  return (doc['role'] ?? '').toString().trim() == 'admin' &&
      (doc['status'] ?? '').toString().trim() == 'active';
});
