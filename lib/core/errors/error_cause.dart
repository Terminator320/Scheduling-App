import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/notices/notice_service.dart';

import 'package:scheduling/l10n/l10n.dart';

/// Sanitized error categories safe to show in the UI — no Firebase codes or
/// stack traces leak through. Full detail still goes to Crashlytics. Each one
/// maps to a cause string that names a next step the user can actually take.
enum _ErrorCause {
  offline,
  permissionDenied,
  notFound,
  signedOut,
  tooManyAttempts,
  invalidData,
  unknown,
}

_ErrorCause _classifyError(Object error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'unavailable' ||
      'network-request-failed' ||
      'deadline-exceeded' => _ErrorCause.offline,
      'permission-denied' => _ErrorCause.permissionDenied,
      'not-found' => _ErrorCause.notFound,
      'unauthenticated' || 'user-token-expired' => _ErrorCause.signedOut,
      'resource-exhausted' ||
      'too-many-requests' => _ErrorCause.tooManyAttempts,
      'invalid-argument' || 'already-exists' => _ErrorCause.invalidData,
      _ => _ErrorCause.unknown,
    };
  }
  if (error is SocketException || error is TimeoutException) {
    return _ErrorCause.offline;
  }
  return _ErrorCause.unknown;
}

/// Composes "{intro}. {cause}" — what failed, then why and what to do next.
///
/// The cause is deliberately actionable rather than diagnostic: the raw error
/// and its Firebase code go to Crashlytics through the call site's
/// `logger.warn`, never to the screen.
String composeErrorNotice(
  BuildContext context, {
  required String intro,
  required Object error,
}) {
  final l10n = context.l10n;
  final cause = switch (_classifyError(error)) {
    _ErrorCause.offline => l10n.error_causeOffline,
    _ErrorCause.permissionDenied => l10n.error_causePermissionDenied,
    _ErrorCause.notFound => l10n.error_causeNotFound,
    _ErrorCause.signedOut => l10n.error_causeSignedOut,
    _ErrorCause.tooManyAttempts => l10n.error_causeTooManyAttempts,
    _ErrorCause.invalidData => l10n.error_causeInvalidData,
    _ErrorCause.unknown => l10n.error_causeUnknown,
  };
  return l10n.error_noticeWithCause(intro, cause);
}

/// Fails a write fast when the device is offline, surfacing the standard
/// offline notice. Returns true when it fired, so the caller returns.
///
/// An awaited Firestore write only resolves on server ack, so without this the
/// button spins until the connection returns. Every widget-layer write guard
/// goes through here: the block was copy-pasted at six call sites differing
/// only in [intro].
///
/// Two surfaces deliberately don't use this, and both keep their own shape for
/// a reason. `AccountSetupScreen` surfaces offline through its own
/// `_bannerError`, not a notice. `WaveSettingsSection._blockedOffline` surfaces
/// `WaveNetwork().toLocalizedMessage` instead, so the offline notice speaks the
/// same typed-`Failure` vocabulary as every other notice that section emits.
/// (This named the two `accept_invite_*` screens until 2026-08-11; P4c deleted
/// both, so a stale carve-out read as drift — keep this list exact.)
bool guardedOffline(
  BuildContext context,
  WidgetRef ref, {
  required String intro,
}) {
  if (!ref.read(isOfflineProvider)) return false;
  ref
      .read(noticeServiceProvider)
      .error(
        composeErrorNotice(
          context,
          intro: intro,
          error: const SocketException('offline'),
        ),
      );
  return true;
}
