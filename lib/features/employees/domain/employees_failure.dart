import 'package:flutter/widgets.dart';

import 'package:scheduling/core/errors/failure.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';

/// Sealed family of typed failures for the employees feature.
///
/// Mirrors the `AuthFailure` shape so the same `failure.toLocalizedMessage`
/// pipeline works for both. Subclasses must not carry any raw error text —
/// keep the user-facing surface fully localized.
sealed class EmployeesFailure extends Failure {
  const EmployeesFailure();
}

/// An attempt to create or update an employee with an email that already
/// exists on another `users` doc. Surfaced both as a field error (under
/// the email TextFormField) and as a banner notice.
class EmployeesFailureEmailAlreadyExists extends EmployeesFailure {
  const EmployeesFailureEmailAlreadyExists();

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.anEmployeeWithThisEmailAlreadyExists;
}
