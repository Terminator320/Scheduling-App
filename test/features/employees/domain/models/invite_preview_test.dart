import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/employees/domain/models/invite_preview.dart';

void main() {
  group('InvitePreview.fromMap', () {
    test('decodes the previewInvite payload', () {
      final expiry = DateTime(2026, 8, 16, 9, 30);
      final preview = InvitePreview.fromMap({
        'email': 'theo@example.com',
        'firstName': 'Theo',
        'lastName': 'Roy',
        'role': 'admin',
        'expiresAtMs': expiry.millisecondsSinceEpoch,
      });

      expect(preview.email, 'theo@example.com');
      expect(preview.firstName, 'Theo');
      expect(preview.lastName, 'Roy');
      expect(preview.role, 'admin');
      expect(preview.isAdmin, isTrue);
      expect(preview.expiresAt, expiry);
    });

    test('defaults the role to employee and the names to empty', () {
      final preview = InvitePreview.fromMap(const {
        'email': 'theo@example.com',
      });

      expect(preview.role, 'employee');
      expect(preview.isAdmin, isFalse);
      expect(preview.firstName, '');
      expect(preview.lastName, '');
    });

    test('a missing expiry is null, never the epoch', () {
      final preview = InvitePreview.fromMap(const {'email': 'a@b.com'});
      expect(preview.expiresAt, isNull);
    });

    test('value equality holds', () {
      final a = InvitePreview.fromMap(const {
        'email': 'a@b.com',
        'expiresAtMs': 1000,
      });
      final b = InvitePreview.fromMap(const {
        'email': 'a@b.com',
        'expiresAtMs': 1000,
      });

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
