import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/shared/widgets/primitives/name_initials.dart';

void main() {
  group('nameInitials', () {
    test('first and last word', () {
      expect(nameInitials('Marc Tremblay'), 'MT');
    });

    test('a single word gives one initial', () {
      expect(nameInitials('Marc'), 'M');
    });

    test('the MIDDLE names are ignored, not concatenated', () {
      expect(nameInitials('Jean Luc Pierre Tremblay'), 'JT');
    });

    test('lowercase input is upcased', () {
      expect(nameInitials('marc tremblay'), 'MT');
    });

    test('blank or whitespace-only input falls back to ?', () {
      expect(nameInitials(''), '?');
      expect(nameInitials('   '), '?');
      expect(nameInitials('\t\n'), '?');
    });

    test('surrounding and repeated whitespace is collapsed', () {
      expect(nameInitials('  Marc   Tremblay  '), 'MT');
    });

    test('an accented initial keeps its accent', () {
      expect(nameInitials('Élodie Berger'), 'ÉB');
    });

    test('a name outside the BMP yields a whole grapheme, not half a '
        'surrogate pair', () {
      // `word[0]` indexes a UTF-16 code UNIT, so a supplementary-plane first
      // character came back as a lone surrogate and rendered as a replacement
      // box on the avatar. `.characters` takes the whole grapheme.
      const emojiName = '\u{1F600} Tremblay';
      final initials = nameInitials(emojiName);

      expect(initials.startsWith('\u{1F600}'), isTrue);
      expect(initials, '\u{1F600}T');
      // A lone surrogate would be a single code unit in the D800-DFFF range.
      expect(
        initials.codeUnitAt(0),
        isNot(inInclusiveRange(0xDC00, 0xDFFF)),
        reason: 'must not start on a trailing surrogate',
      );
    });

    test('a combining mark rides along with its base letter', () {
      // "e" + U+0301 is one grapheme but two code units; `[0]` dropped the
      // accent silently.
      const decomposed = 'élodie Berger';
      expect(nameInitials(decomposed).characters.first, 'é'.toUpperCase());
    });
  });
}
