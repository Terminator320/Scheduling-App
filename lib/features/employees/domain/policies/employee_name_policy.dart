/// Placeholder used only when a record has no name at all. Never an empty
/// string: it is what the roster renders and what `_sortKeyFor` orders on, so
/// an unnamed user would otherwise appear as a blank row that sorts first.
/// (It also used to guard a Firestore `orderBy('name')` on `watchAllUsers`,
/// which would have excluded the doc outright — that ordering is gone, and the
/// sort happens in Dart now, but the placeholder is still load-bearing.)
const String kUnnamedEmployee = '-';

/// The single place `users.name` is built. Every write path routes through it -
/// P4 adds first/last names but never stops populating the composed `name`.
String composeEmployeeName({
  required String firstName,
  required String lastName,
  required String fallback,
}) {
  final composed = [
    firstName.trim(),
    lastName.trim(),
  ].where((part) => part.isNotEmpty).join(' ');
  if (composed.isNotEmpty) return composed;
  final stored = fallback.trim();
  return stored.isNotEmpty ? stored : kUnnamedEmployee;
}

/// Best-effort UI/display name for an employee record.
///
/// Uses the split-name fields first, then the stored composed name, then the
/// email as a last meaningful identifier before falling back to the unnamed
/// placeholder.
String displayEmployeeName({
  required String firstName,
  required String lastName,
  required String name,
  required String email,
}) => composeEmployeeName(
  firstName: firstName,
  lastName: lastName,
  fallback: name.trim().isNotEmpty ? name : email,
);
