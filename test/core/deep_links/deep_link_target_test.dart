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

    test('ignores an invite link — the code flow is retired', () {
      // Employees now sign in with credentials their admin gives them, so an
      // old invite URL must fall through rather than open a dead screen.
      expect(
        classifyDeepLink(
          Uri.parse('esproschedule://invite?code=ABCD-EFGH-JKMN'),
        ),
        isA<IgnoredLink>(),
      );
      expect(
        classifyDeepLink(Uri.parse('esproschedule://invite')),
        isA<IgnoredLink>(),
      );
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
