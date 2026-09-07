import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/analytics/analytics_providers.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';

/// Keeps the `user_role` analytics user property in step with the LIVE account
/// document — a sibling of `AppSyncListeners`, registered from `build`.
///
/// The role is read from Firestore rather than anywhere cached, for the same
/// reason every other role gate in this app is: a stale role here would
/// misattribute every event for the rest of the session, and the resulting
/// report ("employees use the dashboard heavily") reads perfectly plausible.
///
/// A null/empty role CLEARS the property. That covers sign-out, and it covers
/// the bootstrap window a fresh sign-in passes through, where the doc is
/// settled-but-empty — attributing that window to the previous session's role
/// is exactly the misattribution the live read exists to avoid.
///
/// The uid is never sent. `setUserId` is not called anywhere in this app.
class AnalyticsIdentityListener {
  const AnalyticsIdentityListener(this.ref);

  final WidgetRef ref;

  void registerAll() => _userRole();

  void _userRole() {
    ref.listen<AsyncValue<String>>(userRoleProvider, (previous, next) {
      // An unsettled read says nothing about the role — holding the last known
      // value beats blanking it on every transient Firestore hiccup.
      if (next.isLoading || next.hasError) return;
      final role = next.value ?? '';
      if (previous?.value == role) return;
      ref
          .read(analyticsServiceProvider)
          .setUserRole(role.isEmpty ? null : role);
    });
  }
}
