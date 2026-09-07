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
/// Fails CLOSED whenever the doc is unsettled, errored or EMPTY, matching the
/// least-privilege default every appointment surface already takes. That last
/// case is not hypothetical — a settled empty doc is the bootstrap window a
/// fresh sign-in and a cold cache both pass through — so this can read false
/// for an admin for as long as that window lasts, and every consumer must be
/// able to survive being told so. It is the same answer `readAccountGateInputs`
/// gives in the same window, and the app-wide handling of a genuinely empty doc
/// belongs to `SplashScreen` and `AccountExitListeners`, not here.
final isActiveAdminProvider = Provider<bool>((ref) {
  final doc = ref.watch(currentUserDocProvider).value;
  if (doc == null) return false;
  return (doc['role'] ?? '').toString().trim() == 'admin' &&
      (doc['status'] ?? '').toString().trim() == 'active';
});
