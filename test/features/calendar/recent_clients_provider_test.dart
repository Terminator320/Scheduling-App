import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/recent_client.dart';

void main() {
  AppointmentRecord booking({
    required String clientId,
    required String name,
    required String phone,
    required int day,
    String address = '',
  }) => AppointmentRecord(
    startTime: DateTime(2026, 9, day),
    endTime: DateTime(2026, 9, day, 1),
    clientId: clientId,
    clientName: name,
    clientPhone: phone,
    address: address,
  );

  group('recentClientsFrom', () {
    test('keeps newest-first order and drops repeats', () {
      final recents = recentClientsFrom([
        booking(clientId: 'c1', name: 'Marie', phone: '5145628332', day: 5),
        booking(clientId: 'c2', name: 'Nordelec', phone: '5145550110', day: 4),
        booking(clientId: 'c1', name: 'Marie', phone: '5145628332', day: 3),
      ]);
      expect(recents.map((r) => r.clientId).toList(), ['c1', 'c2']);
    });

    test('drops personal jobs and rows with no client', () {
      final recents = recentClientsFrom([
        booking(clientId: '', name: '', phone: '', day: 5),
        booking(clientId: 'c1', name: 'Marie', phone: '5145628332', day: 4),
      ]);
      expect(recents.map((r) => r.clientId).toList(), ['c1']);
    });

    test('carries the job address of the most recent booking', () {
      final recents = recentClientsFrom([
        booking(
          clientId: 'c1',
          name: 'Marie',
          phone: '5145628332',
          address: '4820 rue Wellington',
          day: 5,
        ),
        booking(
          clientId: 'c1',
          name: 'Marie',
          phone: '5145628332',
          address: '1250 boul. LaSalle',
          day: 3,
        ),
      ]);
      expect(recents.single.address, '4820 rue Wellington');
    });

    test('caps the list', () {
      final recents = recentClientsFrom([
        for (var i = 0; i < 80; i++)
          booking(clientId: 'c$i', name: 'C$i', phone: '514555$i', day: 1),
      ], limit: 25);
      expect(recents, hasLength(25));
    });
  });

  group('matchesDigits', () {
    test('matches a substring of the phone', () {
      const recent = (
        clientId: 'c1',
        name: 'Marie Tremblay',
        phone: '5145628332',
        address: '',
      );
      expect(matchesDigits(recent, '514'), isTrue);
      expect(matchesDigits(recent, '5628'), isTrue);
      expect(matchesDigits(recent, '999'), isFalse);
    });

    test('an empty query matches everything', () {
      const recent = (
        clientId: 'c1',
        name: 'Marie Tremblay',
        phone: '5145628332',
        address: '',
      );
      expect(matchesDigits(recent, ''), isTrue);
    });
  });
}
