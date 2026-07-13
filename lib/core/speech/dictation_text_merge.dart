import 'package:characters/characters.dart';

/// Result of splicing dictated text into a field snapshot.
typedef DictationMerge = ({String text, int caret});

/// Splices [recognized] into [base] at [insertAt] (the caret captured when
/// dictation started). Each partial result replays against the same snapshot,
/// so calling this repeatedly with growing [recognized] is stable.
///
/// Adds a separating space when the character before the splice point is not
/// whitespace. [maxLength] caps the inserted segment (grapheme-counted, like
/// TextField.maxLength) while always preserving [base] intact.
DictationMerge mergeDictation({
  required String base,
  required int insertAt,
  required String recognized,
  int? maxLength,
}) {
  final at = insertAt.clamp(0, base.length);
  var segment = recognized;
  if (segment.isNotEmpty && at > 0 && base[at - 1].trim().isNotEmpty) {
    segment = ' $segment';
  }
  if (maxLength != null) {
    final allowed = maxLength - base.characters.length;
    segment = allowed <= 0 ? '' : segment.characters.take(allowed).toString();
  }
  final text = base.substring(0, at) + segment + base.substring(at);
  return (text: text, caret: at + segment.length);
}
