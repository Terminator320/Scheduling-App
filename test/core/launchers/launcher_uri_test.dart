// Pins the two pure URI rules behind the shared launchers. The launches
// themselves are plugin calls (device-only), but these derivations are where
// the real failures live: a tel: path some dialers reject, and a link that
// opens nothing.

import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/launchers/phone_call_launcher.dart';
import 'package:scheduling/core/launchers/web_url_launcher.dart';

void main() {
  group('dialableUri', () {
    test('strips the stored formatting to bare digits', () {
      // Numbers are STORED formatted, and Uri would percent-encode the
      // brackets and space into the path.
      expect(dialableUri('(514) 555-1234').toString(), 'tel:5145551234');
    });

    test('keeps a leading + so an international number still dials', () {
      expect(dialableUri('+1 (514) 555-1234').toString(), 'tel:+15145551234');
    });

    test('keeps extension digits appended past the tenth', () {
      // PhoneInputFormatter appends them verbatim rather than truncating, so
      // they reach here.
      expect(dialableUri('(514) 555-1234 567').toString(), 'tel:5145551234567');
    });

    test('falls back to the raw text when there are no digits', () {
      expect(dialableUri('  CALL-ME  ').toString(), 'tel:CALL-ME');
    });
  });

  group('parseWebUrl', () {
    test('accepts an ordinary https link', () {
      expect(parseWebUrl('https://example.com/terms')?.host, 'example.com');
    });

    test('trims surrounding whitespace', () {
      expect(parseWebUrl('  https://example.com  '), isNotNull);
    });

    test('rejects a bare host with no scheme', () {
      // launchUrl accepts this and then fails at the platform boundary.
      expect(parseWebUrl('example.com'), isNull);
    });

    test('rejects a scheme with no authority', () {
      expect(parseWebUrl('https:'), isNull);
    });

    test('rejects non-web schemes even when they have an authority', () {
      expect(parseWebUrl('ftp://example.com/file'), isNull);
    });

    test('rejects empty and whitespace', () {
      expect(parseWebUrl(''), isNull);
      expect(parseWebUrl('   '), isNull);
    });
  });
}
