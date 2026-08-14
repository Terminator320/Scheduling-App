import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/images/image_magic.dart';

/// Worked examples shared with `functions/__tests__/image_magic.test.js`.
///
/// `hasValidImageMagic` exists on both sides of a hand-mirrored pair, and the
/// server half DELETES an object whose check fails. A divergence is therefore
/// not "two validators disagree" — it is a photo that uploads successfully and
/// is then silently removed. These cases are duplicated verbatim in the jest
/// suite so a drift fails a test on whichever side moved.
void main() {
  group('hasValidImageMagic', () {
    test('accepts a JPEG signature', () {
      expect(hasValidImageMagic(const [0xFF, 0xD8, 0xFF, 0xE0]), isTrue);
    });

    test('accepts a PNG signature', () {
      expect(hasValidImageMagic(const [0x89, 0x50, 0x4E, 0x47]), isTrue);
    });

    test('rejects the three PNG bytes with the wrong fourth', () {
      // The regression this pair was reconciled for: the client used to accept
      // this and the server deleted it after upload.
      expect(hasValidImageMagic(const [0x89, 0x50, 0x4E, 0x00]), isFalse);
    });

    test('rejects a three-byte PNG prefix', () {
      expect(hasValidImageMagic(const [0x89, 0x50, 0x4E]), isFalse);
    });

    test('accepts a three-byte JPEG prefix', () {
      // Asymmetric with PNG on purpose — the JS never indexes the fourth byte
      // on this branch, so both sides accept it.
      expect(hasValidImageMagic(const [0xFF, 0xD8, 0xFF]), isTrue);
    });

    test('rejects an empty file', () {
      expect(hasValidImageMagic(const []), isFalse);
    });

    test('rejects a GIF signature', () {
      expect(hasValidImageMagic(const [0x47, 0x49, 0x46, 0x38]), isFalse);
    });

    test('rejects a PDF signature', () {
      expect(hasValidImageMagic(const [0x25, 0x50, 0x44, 0x46]), isFalse);
    });

    test('rejects a truncated JPEG prefix', () {
      expect(hasValidImageMagic(const [0xFF, 0xD8]), isFalse);
    });
  });
}
