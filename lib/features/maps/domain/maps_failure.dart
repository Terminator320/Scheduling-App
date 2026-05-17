import 'package:flutter/widgets.dart';

import 'package:scheduling/core/errors/failure.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';

sealed class MapsFailure extends Failure {
  const MapsFailure({this.cause, this.stackTrace});

  final Object? cause;
  final StackTrace? stackTrace;
}

class MapsFailureNetwork extends MapsFailure {
  const MapsFailureNetwork({super.cause, super.stackTrace});

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.addressLookupFailed;
}

class MapsFailureParse extends MapsFailure {
  const MapsFailureParse({super.cause, super.stackTrace});

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.couldNotLoadAddressDetails;
}

class MapsFailureRateLimit extends MapsFailure {
  const MapsFailureRateLimit({super.cause, super.stackTrace});

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.tooManyAttemptsPleaseTryAgainLater2;
}

class MapsFailureUnauthorized extends MapsFailure {
  const MapsFailureUnauthorized({super.cause, super.stackTrace});

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.somethingWentWrongPleaseTryAgain;
}

class MapsFailureInvalidInput extends MapsFailure {
  const MapsFailureInvalidInput({super.cause, super.stackTrace});

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.somethingWentWrong;
}
