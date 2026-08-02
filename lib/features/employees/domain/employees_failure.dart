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
      context.l10n.error_anEmployeeWithThisEmailAlreadyExists;
}

/// `revokeInvite` refused: the invite was redeemed or already revoked between
/// the roster row rendering and the tap. Both server rejections
/// (`invite-not-pending`, `invite-not-found`) collapse here — the admin needs
/// the same thing said either way, and the live stream has already dropped or
/// flipped the row.
class EmployeesFailureInviteNoLongerPending extends EmployeesFailure {
  const EmployeesFailureInviteNoLongerPending();

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.error_thatInviteIsNoLongerPending;
}

class EmployeesFailureUnknown extends EmployeesFailure {
  const EmployeesFailureUnknown();

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.error_somethingWentWrongPleaseTryAgain;
}
