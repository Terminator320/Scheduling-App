/// Hoisted: Dart recompiles a regex literal on every evaluation, and a crew
/// stack builds one avatar per assignee per card.
final _whitespace = RegExp(r'\s+');

/// Two-letter initials from the first and last word of a name. Blank input
/// returns '?'.
String nameInitials(String name) {
  final parts = name.trim().split(_whitespace);
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
