/// Two-letter initials for [name] — first + last word, uppercased. A single
/// word yields its first letter; blank/empty input yields `'?'`. Extracted from
/// `AppAvatar` so the live-map marker renderer reuses the exact same rule.
String nameInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
