import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';

import 'package:scheduling/features/maps/domain/maps_failure.dart';

class MapsErrorMapper {
  const MapsErrorMapper._();

  static MapsFailure map(Object error, [StackTrace? stackTrace]) {
    if (error is MapsFailure) return error;

    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'resource-exhausted':
          return MapsFailureRateLimit(
            cause: error,
            stackTrace: stackTrace,
          );
        case 'unauthenticated':
        case 'failed-precondition':
          return MapsFailureUnauthorized(
            cause: error,
            stackTrace: stackTrace,
          );
        case 'invalid-argument':
          return MapsFailureInvalidInput(
            cause: error,
            stackTrace: stackTrace,
          );
        default:
          return MapsFailureNetwork(
            cause: error,
            stackTrace: stackTrace,
          );
      }
    }

    if (error is FormatException || error is JsonUnsupportedObjectError) {
      return MapsFailureParse(cause: error, stackTrace: stackTrace);
    }

    return MapsFailureNetwork(cause: error, stackTrace: stackTrace);
  }
}
