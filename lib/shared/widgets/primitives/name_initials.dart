/// Two-letter initials from the first and last word of a name. Blank input
/// returns '?'.
String nameInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
