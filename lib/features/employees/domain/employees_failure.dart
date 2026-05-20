import 'package:flutter/widgets.dart';

import 'package:scheduling/core/errors/failure.dart';
import 'package:scheduling/l10n/l10n.dart';

sealed class EmployeesFailure extends Failure {
  const EmployeesFailure();
}

class EmployeesFailureEmailAlreadyExists extends EmployeesFailure {
  const EmployeesFailureEmailAlreadyExists();

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.anEmployeeWithThisEmailAlreadyExists;
}
