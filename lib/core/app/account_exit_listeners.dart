import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/app/app_sync_listeners.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/feedback/error_snack_bar.dart';

/// Forces a sign-out the moment the signed-in user loses access — their
/// account is disabled, their admin role is revoked, or the doc is deleted
/// out from under them.
///
/// Pulled out of `main.dart` because the teardown ORDER is load-bearing and
/// the reentrancy guard is subtle enough to want a test: as a private `State`
/// method on the app root, neither could be exercised. Sibling of
/// [AppSyncListeners], which owns the non-lifecycle wiring.
///
/// [registerAll] must be called from `build`, like any `ref.listen`.
class AccountExitListeners {
  AccountExitListeners({
    required this.ref,
    required this.navigatorKey,
    required this.scaffoldMessengerKey,
    required this.isMounted,
  });

  final WidgetRef ref;
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;

  /// The host `State`'s mounted flag — the cold-start deletion check resolves
  /// asynchronously and must not act on a torn-down tree.
  final bool Function() isMounted;

  /// One exit at a time. Three listeners can fire for the same underlying
  /// event (a delete flips status AND empties the doc), and each would
  /// otherwise start its own de-registration + navigation.
  bool _isHandlingAccountExit = false;

  void registerAll() {
    _listenForAccountDisabled();
    _listenForRoleRevocation();
    _listenForDeletedAccount();
  }

  /// De-registers this device, signs out, and lands on login with a notice.
  ///
  /// The order matters: push, presence and Live Activity registration are all
  /// torn down BEFORE `signOut()`, because each needs the credential that
  /// sign-out revokes. Each is best-effort — a failure there must not block
  /// the sign-out, which is the part that actually protects the user.
  Future<void> handleAccountExit(
    String Function(AppLocalizations) selectMessage,
  ) async {
    if (_isHandlingAccountExit) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    final navContext = navigatorKey.currentContext;
    if (navContext == null) return;
    _isHandlingAccountExit = true;

    var exitScheduled = false;
    try {
      final message = selectMessage(AppLocalizations.of(navContext));
      // Best-effort de-registration first — a failure here shouldn't block
      // sign-out.
      await ref
          .read(pushRegistrationControllerProvider)
          .unregisterCurrentDevice();
      await ref.read(presenceSyncControllerProvider).unregister();
      await ref.read(liveActivityRegistrationControllerProvider).unregister();
      await ref.read(authServiceProvider).signOut();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          AppRoutes.login,
          (_) => false,
        );
        scaffoldMessengerKey.currentState?.showSnackBar(
          errorSnackBar(navContext, message),
        );
        _isHandlingAccountExit = false;
      });
      exitScheduled = true;
    } catch (e, st) {
      // Sign-out failed — next signal retries.
      ref.read(loggerProvider).warn('ACCOUNT-EXIT sign-out failed', e, st);
    } finally {
      // Reset on failure to allow retry on next signal. On success the
      // post-frame callback owns the reset, so the guard stays up until the
      // navigation actually happens.
      if (!exitScheduled) _isHandlingAccountExit = false;
    }
  }

  void _listenForAccountDisabled() {
    ref.listen<AsyncValue<bool>>(accountDisabledProvider, (prev, next) {
      final wasDisabled = prev?.value ?? false;
      final isDisabled = next.value ?? false;
      if (!wasDisabled && isDisabled) {
        handleAccountExit((l10n) => l10n.error_thisAccountHasBeenDisabled);
      }
    });
  }

  void _listenForRoleRevocation() {
    ref.listen<AsyncValue<String>>(userRoleProvider, (prev, next) {
      final prevRole = prev?.value;
      final nextRole = next.value;
      // An empty role means deletion, not demotion — let
      // _listenForDeletedAccount handle that case.
      if (prevRole == 'admin' &&
          nextRole != null &&
          nextRole != '' &&
          nextRole != 'admin') {
        handleAccountExit((l10n) => l10n.error_yourAdminAccessWasRevoked);
      }
    });
  }

  void _listenForDeletedAccount() {
    ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
      prev,
      next,
    ) {
      final isSignedIn = FirebaseAuth.instance.currentUser != null;
      final resolvedUid = ref.read(authUidProvider).value;
      // Kick the user out on a populated→empty transition. Cold-start
      // deletion is handled separately, below.
      if (isAccountDeletionSignal(
        isSignedIn: isSignedIn,
        resolvedUid: resolvedUid,
        previous: prev,
        docState: next,
      )) {
        handleAccountExit((l10n) => l10n.error_thisAccountHasBeenDisabled);
        return;
      }
      unawaited(
        confirmColdStartDeletion(
          isSignedIn: isSignedIn,
          resolvedUid: resolvedUid,
          previous: prev,
          docState: next,
          loadWarmCache: ref.read(authCacheProvider).loadIfMatch,
          logger: ref.read(loggerProvider),
        ).then((deleted) {
          if (deleted && isMounted()) {
            handleAccountExit((l10n) => l10n.error_thisAccountHasBeenDisabled);
          }
        }),
      );
    });
  }
}
