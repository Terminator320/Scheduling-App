import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/account_deletion_service.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';

final selfEmailServiceProvider = Provider<SelfEmailService>(
  (ref) => SelfEmailService(
    deletionService: ref.watch(accountDeletionServiceProvider),
    logger: ref.watch(loggerProvider),
  ),
);

/// Moves the signed-in person's OWN sign-in address.
///
/// Re-auth FIRST, then the callable, and the order is the point: reversing them
/// would let an unattended unlocked phone move the address and only then
/// discover it could not prove who it was — by which time Auth has already
/// changed. `reauthenticateWithPassword` is reused rather than re-derived; it
/// already exists for exactly this shape on account deletion.
///
/// The callable — not a Firestore write — because `email` is a sign-in
/// identity: Auth and the users doc move together through `changeEmployeeEmail`
/// or not at all. `email` is deliberately absent from the self-service rules
/// allowlist, so a direct write would be rejected anyway.
class SelfEmailService {
  SelfEmailService({
    required AccountDeletionService deletionService,
    required AppLogger logger,
    FirebaseFunctions? functions,
  }) : _deletionService = deletionService,
       _logger = logger,
       _functions = functions ?? FirebaseFunctions.instance;

  final AccountDeletionService _deletionService;
  final AppLogger _logger;
  final FirebaseFunctions _functions;

  /// Throws a typed failure — [EmployeesFailureEmailAlreadyExists] when the
  /// address is taken, or an [AuthFailure] from the re-auth step.
  Future<void> changeOwnEmail({
    required String docId,
    required String email,
    required String password,
  }) async {
    // Lets an AuthFailure (wrong password, requires-recent-login, offline)
    // propagate untouched — AuthErrorMapper has already shaped it, and the
    // catch site logs through logger.authFailure.
    await _deletionService.reauthenticateWithPassword(password);
    try {
      await _functions
          .httpsCallable(
            'changeEmployeeEmail',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call<dynamic>({'docId': docId, 'email': email});
    } on FirebaseFunctionsException catch (e, st) {
      if (e.message == 'email-exists') {
        throw const EmployeesFailureEmailAlreadyExists();
      }
      // Never the address — emails are PII and this reaches Crashlytics.
      _logger.warn('ME-EMAIL changeEmployeeEmail failed', e, st);
      throw const AuthFailureUnknown();
    }
  }
}
