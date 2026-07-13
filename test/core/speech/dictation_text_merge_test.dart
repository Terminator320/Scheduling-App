import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/speech/dictation_text_merge.dart';

void main() {
  group('mergeDictation', () {
    test('inserts recognized text into an empty field', () {
      final m = mergeDictation(
        base: '',
        insertAt: 0,
        recognized: 'hello world',
      );
      expect(m.text, 'hello world');
      expect(m.caret, 11);
    });

    test(
      'appends with a separating space when base does not end in whitespace',
      () {
        final m = mergeDictation(
          base: 'call client',
          insertAt: 11,
          recognized: 'tomorrow',
        );
        expect(m.text, 'call client tomorrow');
        expect(m.caret, 20);
      },
    );

    test('adds no extra space when base already ends in whitespace', () {
      final m = mergeDictation(
        base: 'call client ',
        insertAt: 12,
        recognized: 'tomorrow',
      );
      expect(m.text, 'call client tomorrow');
    });

    test('splices at a mid-text caret and leaves the tail intact', () {
      final m = mergeDictation(
        base: 'before after',
        insertAt: 6,
        recognized: 'now',
      );
      expect(m.text, 'before now after');
      expect(m.caret, 10);
    });

    test('clamps an out-of-range caret to the end of base', () {
      final m = mergeDictation(base: 'abc', insertAt: 99, recognized: 'def');
      expect(m.text, 'abc def');
    });

    test('caps the inserted segment at maxLength and preserves base', () {
      final m = mergeDictation(
        base: '12345',
        insertAt: 5,
        recognized: 'abcdef',
        maxLength: 8,
      );
      expect(m.text, '12345 ab');
      expect(m.text.length, 8);
    });

    test('inserts nothing when base already fills maxLength', () {
      final m = mergeDictation(
        base: '12345',
        insertAt: 5,
        recognized: 'abc',
        maxLength: 5,
      );
      expect(m.text, '12345');
      expect(m.caret, 5);
    });

    test(
      'replaying successive partials against the same snapshot is stable',
      () {
        final first = mergeDictation(
          base: 'note:',
          insertAt: 5,
          recognized: 'buy',
        );
        final second = mergeDictation(
          base: 'note:',
          insertAt: 5,
          recognized: 'buy pipe',
        );
        expect(first.text, 'note: buy');
        expect(second.text, 'note: buy pipe');
      },
    );
  });
}
