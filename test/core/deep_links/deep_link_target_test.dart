import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/deep_links/deep_link_target.dart';

void main() {
  group('classifyDeepLink', () {
    test('reads the appointment id off an appointment link', () {
      final target = classifyDeepLink(
        Uri.parse('esproschedule://appointment?id=abc123'),
      );

      expect((target as AppointmentLink).id, 'abc123');
    });

    test('trims whitespace around the appointment id', () {
      final target = classifyDeepLink(
        Uri.parse('esproschedule://appointment?id=%20abc123%20'),
      );

      expect((target as AppointmentLink).id, 'abc123');
    });

    test('yields an empty appointment id when the param is missing', () {
      final target = classifyDeepLink(
        Uri.parse('esproschedule://appointment'),
      );

      expect((target as AppointmentLink).id, '');
    });

    test('reads the code off an invite link', () {
      final target = classifyDeepLink(
        Uri.parse('esproschedule://invite?code=ABCD-EFGH-JKMN'),
      );

      expect((target as InviteLink).code, 'ABCD-EFGH-JKMN');
    });

    test('yields an empty code when the invite param is missing', () {
      final target = classifyDeepLink(Uri.parse('esproschedule://invite'));

      expect((target as InviteLink).code, '');
    });

    test('yields an empty code when the invite param is blank', () {
      final target = classifyDeepLink(
        Uri.parse('esproschedule://invite?code='),
      );

      expect((target as InviteLink).code, '');
    });

    test('ignores a valueless homeWidget param on an appointment link', () {
      final target = classifyDeepLink(
        Uri.parse('esproschedule://appointment?id=abc123&homeWidget'),
      );

      expect(target, isA<IgnoredLink>());
    });

    test('ignores a valued homeWidget param on an appointment link', () {
      final target = classifyDeepLink(
        Uri.parse('esproschedule://appointment?id=abc123&homeWidget=x'),
      );

      expect(target, isA<IgnoredLink>());
    });

    test('ignores a homeWidget param that leads the query string', () {
      final target = classifyDeepLink(
        Uri.parse('esproschedule://appointment?homeWidget&id=abc123'),
      );

      expect(target, isA<IgnoredLink>());
    });

    test('ignores a homeWidget param on an invite link', () {
      final target = classifyDeepLink(
        Uri.parse('esproschedule://invite?code=ABC&homeWidget=1'),
      );

      expect(target, isA<IgnoredLink>());
    });

    test('ignores a foreign scheme', () {
      final target = classifyDeepLink(
        Uri.parse('https://example.com/invite?code=ABC'),
      );

      expect(target, isA<IgnoredLink>());
    });

    test('ignores an unknown host', () {
      final target = classifyDeepLink(Uri.parse('esproschedule://settings'));

      expect(target, isA<IgnoredLink>());
    });

    test('ignores a scheme-only URL with no host', () {
      final target = classifyDeepLink(Uri.parse('esproschedule://'));

      expect(target, isA<IgnoredLink>());
    });
  });
}
