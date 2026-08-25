import 'package:flutter/widgets.dart';

/// Hoisted: Dart recompiles a regex literal on every evaluation, and a crew
/// stack builds one avatar per assignee per card.
final _whitespace = RegExp(r'\s+');

/// Two-letter initials from the first and last word of a name. Blank input
/// returns '?'.
///
/// Takes the first GRAPHEME of each word, not `word[0]`, which indexes a
/// UTF-16 code unit: a name starting outside the BMP (an emoji, or a
/// supplementary-plane script) yielded a lone surrogate half that renders as a
/// replacement box on the avatar. A combining accent has the same shape —
/// `[0]` keeps the base letter and drops the mark.
String nameInitials(String name) {
  final parts = name.trim().split(_whitespace);
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  final first = _firstGrapheme(parts.first);
  if (parts.length == 1) return first.toUpperCase();
  return '$first${_firstGrapheme(parts.last)}'.toUpperCase();
}

String _firstGrapheme(String word) {
  final characters = word.characters;
  return characters.isEmpty ? '' : characters.first;
}
