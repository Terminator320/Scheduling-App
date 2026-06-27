import 'package:flutter/widgets.dart';

// Base of the typed-failure hierarchy. Implements Exception so repositories
// and services can `throw` failures without tripping only_throw_errors.
@immutable
abstract class Failure implements Exception {
  const Failure();

  String toLocalizedMessage(BuildContext context);
}
