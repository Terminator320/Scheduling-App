import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/navigation/hub_shell_scope.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';

/// Re-routes a signed-in employee the moment an admin promotes them.
///
/// The hub is built once per role, so a person whose `role` flips to `admin`
/// mid-session would otherwise keep the employee shell — and its
/// employee-scoped appointment stream — until they signed out and back in.
///
/// Role is always re-read from Firestore, never from a cache: that is the
/// standing rule for anything that gates access.
///
/// Lives here rather than on the calendar screen because it is a session
/// concern that merely happened to be hosted there — the same reasoning as
/// `PhotoUploadFailureListener` beside it.
class RoleUpgradeListener extends ConsumerStatefulWidget {
  const RoleUpgradeListener({
    required this.child,
    required this.employeeId,
    super.key,
    this.isAdmin = false,
  });

  final Widget child;
  final String employeeId;

  /// Already an admin — nothing to watch for.
  final bool isAdmin;

  @override
  ConsumerState<RoleUpgradeListener> createState() =>
      _RoleUpgradeListenerState();
}

class _RoleUpgradeListenerState extends ConsumerState<RoleUpgradeListener> {
  /// Guards against firing more than once — the post-frame route lands after
  /// several rebuilds of this listener.
  bool _upgrading = false;

  void _upgradeIfAdmin(String? role) {
    if (role != 'admin' || !mounted || _upgrading) return;
    _upgrading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      navigateToDestination(
        context,
        HubTab.calendar,
        isAdmin: true,
        employeeId: widget.employeeId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAdmin) {
      ref.listen<AsyncValue<String>>(
        userRoleProvider,
        (_, next) => _upgradeIfAdmin(next.value),
      );
      // Also checked eagerly: the listener only fires on a CHANGE, so a role
      // that was already 'admin' when this mounted would never reach it.
      _upgradeIfAdmin(ref.read(userRoleProvider).value);
    }
    return widget.child;
  }
}
