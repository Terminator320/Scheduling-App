import 'package:cloud_functions/cloud_functions.dart';

import 'package:scheduling/features/wave/domain/wave_failure.dart';

class WaveErrorMapper {
  const WaveErrorMapper._();

  static WaveFailure map(Object error) {
    if (error is WaveFailure) return error;

    if (error is FirebaseFunctionsException) {
      return _fromException(error);
    }

    return const WaveUnknown();
  }

  static WaveFailure _fromException(FirebaseFunctionsException e) {
    // Match on message first for wave/* semantic codes, then fall back to code.
    final msg = e.message ?? '';

    if (msg == 'wave/token-invalid') return const WaveAuthInvalid();

    if (msg == 'wave/rate-limited' || e.code == 'resource-exhausted') {
      return const WaveRateLimited();
    }

    if (msg == 'wave/network' || e.code == 'unavailable') {
      return const WaveNetwork();
    }

    if (msg == 'wave/validation' || e.code == 'invalid-argument') {
      return const WaveValidation();
    }

    if (msg == 'wave/not-bootstrapped') {
      return const WaveValidation(reason: 'notConnected');
    }

    // Ambiguous: multiple businesses on this token and no picker yet, so be truthful.
    if (msg == 'wave/business-ambiguous') {
      return const WaveValidation(reason: 'businessAmbiguous');
    }

    if (msg == 'wave/business-not-found') {
      return const WaveValidation();
    }

    if (msg == 'wave/not-admin') return const WaveUnknown();

    if (msg == 'wave/unknown' || e.code == 'internal') {
      return const WaveUnknown();
    }

    return const WaveUnknown();
  }
}
