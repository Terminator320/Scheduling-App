import 'package:flutter/widgets.dart';

import 'package:scheduling/l10n/l10n.dart';

// Base of the typed-failure hierarchy. Implements Exception so repositories
// and services can `throw` failures without tripping only_throw_errors.
@immutable
// ignore: one_member_abstracts
abstract class Failure implements Exception {
  const Failure();

  String toLocalizedMessage(BuildContext context);
}

class UnknownFailure extends Failure {
  const UnknownFailure({required this.cause, required this.stackTrace});

  final Object cause;
  final StackTrace stackTrace;

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.error_somethingWentWrongPleaseTryAgain;
}
