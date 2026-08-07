import 'package:flutter/widgets.dart';

// Base of the typed-failure hierarchy. Implements Exception so repositories
// can `throw` failures without tripping the only_throw_errors lint.
@immutable
abstract class Failure implements Exception {
  const Failure();

  String toLocalizedMessage(BuildContext context);
}
