import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/app/account_exit_controller.dart';
import 'package:scheduling/core/app/app_sync_listeners.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/l10n/l10n.dart';

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
    bool Function()? isSignedIn,
  }) : isSignedIn = isSignedIn ?? _firebaseSignedIn;

  static bool _firebaseSignedIn() => FirebaseAuth.instance.currentUser != null;

  final WidgetRef ref;
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;

  /// Injectable so the teardown ORDER and the reentrancy guard can actually be
  /// tested — reading `FirebaseAuth.instance` inline is what kept this class
  /// uncovered despite its own doc calling the order load-bearing. Production
  /// passes nothing and gets the real singleton.
  final bool Function() isSignedIn;

  /// The host `State`'s mounted flag — the cold-start deletion check resolves
  /// asynchronously and must not act on a torn-down tree.
  final bool Function() isMounted;

  /// One exit at a time. Three listeners can fire for the same underlying
  /// event (a delete flips status AND empties the doc), and each would
  /// otherwise start its own de-registration + navigation.
  void registerAll() {
    _listenForAccountDisabled();
    _listenForRoleRevocation();
    _listenForDeletedAccount();
  }

  void _listenForAccountDisabled() {
    ref.listen<AsyncValue<bool>>(accountDisabledProvider, (prev, next) {
      final wasDisabled = prev?.value ?? false;
      final isDisabled = next.value ?? false;
      if (!wasDisabled && isDisabled) {
        _triggerAccountExit((l10n) => l10n.error_thisAccountHasBeenDisabled);
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
        _triggerAccountExit((l10n) => l10n.error_yourAdminAccessWasRevoked);
      }
    });
  }

  void _listenForDeletedAccount() {
    ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
      prev,
      next,
    ) {
      final signedIn = isSignedIn();
      final resolvedUid = ref.read(authUidProvider).value;
      // Kick the user out on a populated→empty transition. Cold-start
      // deletion is handled separately, below.
      if (isAccountDeletionSignal(
        isSignedIn: signedIn,
        resolvedUid: resolvedUid,
        previous: prev,
        docState: next,
      )) {
        _triggerAccountExit((l10n) => l10n.error_thisAccountHasBeenDisabled);
        return;
      }
      unawaited(
        confirmColdStartDeletion(
          isSignedIn: signedIn,
          resolvedUid: resolvedUid,
          previous: prev,
          docState: next,
          loadWarmCache: ref.read(authCacheProvider).loadIfMatch,
          logger: ref.read(loggerProvider),
        ).then((deleted) {
          if (deleted && isMounted()) {
            _triggerAccountExit((l10n) => l10n.error_thisAccountHasBeenDisabled);
          }
        }),
      );
    });
  }

  void _triggerAccountExit(String Function(AppLocalizations) selectMessage) {
    unawaited(
      ref.read(accountExitControllerProvider).exitAccount(
        selectMessage: selectMessage,
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: scaffoldMessengerKey,
        isMounted: isMounted,
      ),
    );
  }
}
