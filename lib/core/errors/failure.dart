import 'package:flutter/widgets.dart';

import 'package:scheduling/core/utils/l10n_extensions.dart';

/// Marker base for all repository / domain failures.
///
/// Each feature defines a sealed subclass family in
/// `features/<f>/domain/<f>_failure.dart`. Subclasses must implement
/// `toLocalizedMessage` so the UI can surface a friendly message via the
/// `noticeService.error(...)` pipeline without knowing the failure subtype.
@immutable
abstract class Failure {
  const Failure();

  String toLocalizedMessage(BuildContext context);
}

/// Fallback for errors that don't map cleanly to a feature-specific failure.
///
/// Repositories should always prefer their own typed failure when possible;
/// `UnknownFailure` is a last resort that still goes through Crashlytics via
/// `AppLogger.error(...)` at the catch site.
class UnknownFailure extends Failure {
  const UnknownFailure({required this.cause, required this.stackTrace});

  final Object cause;
  final StackTrace stackTrace;

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.somethingWentWrongPleaseTryAgain;
}
