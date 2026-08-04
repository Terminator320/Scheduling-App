import 'package:flutter/widgets.dart';

import 'package:scheduling/core/errors/failure.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Typed failures for client writes. Mirrors [EmployeesFailure].
sealed class ClientsFailure extends Failure {
  const ClientsFailure();
}

/// The client still has appointments, so deleting it would orphan that
/// history. The `deleteClient` callable refuses with `failed-precondition`.
class ClientsFailureHasHistory extends ClientsFailure {
  const ClientsFailureHasHistory();

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.clients_deleteBlockedHasHistory;
}

/// The client doc was already gone — a concurrent delete, or a stale list.
class ClientsFailureNotFound extends ClientsFailure {
  const ClientsFailureNotFound();

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.clients_deleteFailedNotFound;
}
