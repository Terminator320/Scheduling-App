import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/policies/history_search_policy.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

bool _matches(AppointmentRecord appointment, String query) =>
    historyEntryMatches(
      historyEntryOf(appointment),
      queryText: ClientSearchPolicy.normalize(query),
      queryDigits: ClientSearchPolicy.digitsOnly(query),
    );

Map<String, dynamic> _rawDoc() => <String, dynamic>{
  'title': 'Job',
  'clientName': 'Marie Tremblay',
  'clientPhone': '5145554321',
  'employeeNames': <dynamic>['Marc Dubois'],
};

void main() {
  // Shared value-for-value with `functions/__tests__/search_tokens.test.js`'s
  // "recordMatchesQuery client/employee seam" group.
  group('historyEntryMatches client/employee seam', () {
    final appointment = AppointmentRecord(
      id: 'a1',
      startTime: DateTime(2026, 9, 5, 9),
      endTime: DateTime(2026, 9, 5, 11),
      clientName: 'Marie Tremblay',
      clientPhone: '5145554321',
      employeeNames: const ['Marc Dubois'],
    );

    test('does not match across the client/employee seam', () {
      expect(_matches(appointment, 'tremblay marc'), isFalse);
    });

    test('still matches within either field', () {
      expect(_matches(appointment, 'marie tremblay'), isTrue);
      expect(_matches(appointment, 'marc dubois'), isTrue);
    });

    test('matches the client phone by digits', () {
      expect(_matches(appointment, '555-4321'), isTrue);
    });

    test('an empty query matches nothing', () {
      expect(_matches(appointment, '  '), isFalse);
    });
  });

  group('matchHistoryDocs', () {
    test('reads the seam off the raw map the same way', () {
      final matched = matchHistoryDocs(
        HistorySearchScan(
          docs: [(id: 'a1', data: _rawDoc())],
          query: 'tremblay marc',
        ),
      );
      expect(matched, isEmpty);
    });

    test('keeps a document that matches one field outright', () {
      final matched = matchHistoryDocs(
        HistorySearchScan(docs: [(id: 'a1', data: _rawDoc())], query: 'dubois'),
      );
      expect(matched.map((a) => a.id), ['a1']);
    });
  });
}
