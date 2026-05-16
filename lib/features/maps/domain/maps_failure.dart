import 'package:flutter/widgets.dart';

import 'package:scheduling/core/errors/failure.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';

/// Sealed family of typed failures for the Maps / Places integration.
///
/// Extends [Failure] so consumers can route through
/// `noticeServiceProvider.error(failure.toLocalizedMessage(context))`
/// without the response body or internal error code leaking to the user
/// or Crashlytics.
///
/// `cause` is captured for backend observability only — never read by
/// `toLocalizedMessage`.
sealed class MapsFailure extends Failure {
  const MapsFailure({this.cause, this.stackTrace});

  final Object? cause;
  final StackTrace? stackTrace;
}

/// Network-level failure: HTTP non-200, timeout, missing API key, transport
/// error. The cause is logged but never surfaced.
class MapsFailureNetwork extends MapsFailure {
  const MapsFailureNetwork({super.cause, super.stackTrace});

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.addressLookupFailed;
}

/// Response body could not be parsed as the expected JSON shape.
class MapsFailureParse extends MapsFailure {
  const MapsFailureParse({super.cause, super.stackTrace});

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.couldNotLoadAddressDetails;
}
