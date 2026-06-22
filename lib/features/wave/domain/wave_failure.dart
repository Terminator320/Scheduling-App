import 'package:flutter/widgets.dart';

import 'package:scheduling/core/errors/failure.dart';
import 'package:scheduling/l10n/l10n.dart';

sealed class WaveFailure extends Failure {
  const WaveFailure();
}

class WaveAuthInvalid extends WaveFailure {
  const WaveAuthInvalid();

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.wave_errorAuthInvalid;
}

class WaveRateLimited extends WaveFailure {
  const WaveRateLimited();

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.error_tooManyAttemptsPleaseTryAgainLater;
}

class WaveValidation extends WaveFailure {
  const WaveValidation({this.reason});

  final String? reason;

  @override
  String toLocalizedMessage(BuildContext context) => reason == 'notConnected'
      ? context.l10n.wave_errorNotConnected
      : context.l10n.wave_errorValidation;
}

class WaveNetwork extends WaveFailure {
  const WaveNetwork();

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.error_networkErrorCheckYourConnectionAndTryAgain;
}

class WaveUnknown extends WaveFailure {
  const WaveUnknown();

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.error_somethingWentWrongPleaseTryAgain;
}
