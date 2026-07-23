import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'package:scheduling/l10n/l10n.dart';

/// Sanitized error categories safe for UI without leaking Firebase codes or stack traces; full detail logs to Crashlytics.
enum _ErrorCause { offline, permissionDenied, notFound, unknown }

_ErrorCause _classifyError(Object error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'unavailable' ||
      'network-request-failed' ||
      'deadline-exceeded' => _ErrorCause.offline,
      'permission-denied' => _ErrorCause.permissionDenied,
      'not-found' => _ErrorCause.notFound,
      _ => _ErrorCause.unknown,
    };
  }
  if (error is SocketException || error is TimeoutException) {
    return _ErrorCause.offline;
  }
  return _ErrorCause.unknown;
}

/// Composes "{intro} — {cause}. ({tag})"; the tag must match the catch
/// site's logger.warn prefix so a user report maps to a Crashlytics line.
String composeErrorNotice(
  BuildContext context, {
  required String intro,
  required String tag,
  required Object error,
}) {
  final l10n = context.l10n;
  final cause = switch (_classifyError(error)) {
    _ErrorCause.offline => l10n.error_causeOffline,
    _ErrorCause.permissionDenied => l10n.error_causePermissionDenied,
    _ErrorCause.notFound => l10n.error_causeNotFound,
    _ErrorCause.unknown => l10n.error_causeUnknown,
  };
  return l10n.error_noticeWithCause(intro, cause, tag);
}
