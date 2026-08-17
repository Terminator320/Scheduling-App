import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';

/// Records which of the two severities a call landed on. `authFailure` is an
/// extension, so it dispatches statically — but the `warn`/`breadcrumb` it
/// calls are ordinary instance methods and reach these overrides.
class _RecordingLogger extends AppLogger {
  final List<String> breadcrumbs = [];
  final List<({String label, Object? error})> warnings = [];

  @override
  void breadcrumb(String message) => breadcrumbs.add(message);

  @override
  void warn(String message, [Object? error, StackTrace? stack]) =>
      warnings.add((label: message, error: error));
}

void main() {
  group('AuthFailureLogging.authFailure', () {
    test('an expected failure files a breadcrumb, not an error record', () {
      final logger = _RecordingLogger()
        ..authFailure(
          'AUTH-SIGNIN',
          const AuthFailureWrongCredentials(),
          Exception('wrong-password'),
          StackTrace.empty,
        );

      expect(logger.warnings, isEmpty);
    });

    test('the breadcrumb names the label and the failure type', () {
      final logger = _RecordingLogger()
        ..authFailure(
          'AUTH-SIGNIN',
          const AuthFailureWrongCredentials(),
          Exception('wrong-password'),
          StackTrace.empty,
        );

      expect(
        logger.breadcrumbs.single,
        'AUTH-SIGNIN (AuthFailureWrongCredentials)',
      );
    });

    test('the breadcrumb never carries the credential that failed', () {
      final logger = _RecordingLogger()
        ..authFailure(
          'AUTH-SIGNIN',
          const AuthFailureWrongCredentials(),
          Exception('email=someone@example.com password=Welcome123!'),
          StackTrace.empty,
        );

      expect(
        logger.breadcrumbs.single,
        isNot(anyOf(contains('someone@example.com'), contains('Welcome123!'))),
      );
    });

    test('an unexpected failure files a Crashlytics error record', () {
      final error = Exception('permission-denied');
      final logger = _RecordingLogger()
        ..authFailure(
          'AUTH-SIGNIN',
          const AuthFailurePermissionDenied(),
          error,
          StackTrace.empty,
        );

      expect(logger.warnings.single, (label: 'AUTH-SIGNIN', error: error));
    });

    test('an unexpected failure leaves no breadcrumb of its own', () {
      final logger = _RecordingLogger()
        ..authFailure(
          'AUTH-SIGNIN',
          const AuthFailureUnknown(),
          Exception('boom'),
          StackTrace.empty,
        );

      expect(logger.breadcrumbs, isEmpty);
    });
  });
}
