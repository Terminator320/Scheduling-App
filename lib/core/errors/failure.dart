import 'package:flutter/widgets.dart';

import 'package:scheduling/core/utils/l10n_extensions.dart';

@immutable
abstract class Failure {
  const Failure();

  String toLocalizedMessage(BuildContext context);
}

class UnknownFailure extends Failure {
  const UnknownFailure({required this.cause, required this.stackTrace});

  final Object cause;
  final StackTrace stackTrace;

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.somethingWentWrongPleaseTryAgain;
}
