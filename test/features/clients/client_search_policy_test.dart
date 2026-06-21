import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

// Mirrors the filter predicate in ClientsListView._buildSearchResults exactly,
// so these tests break if the search fields change.
bool _matches(ClientRecord c, String query) {
  final q = ClientSearchPolicy.normalize(query);
  final qDigits = ClientSearchPolicy.digitsOnly(query);
  final text = ClientSearchPolicy.normalize(
    '${c.displayName} ${c.firstName} ${c.lastName}',
  );
  final phoneDigits = ClientSearchPolicy.digitsOnly('${c.phone} ${c.mobile}');
  final matchesText = q.isNotEmpty && text.contains(q);
  final matchesPhone = qDigits.isNotEmpty && phoneDigits.contains(qDigits);
  return matchesText || matchesPhone;
}

void main() {
  group('ClientSearchPolicy.shouldSearch', () {
    test('rejects empty and whitespace queries', () {
      expect(ClientSearchPolicy.shouldSearch(''), isFalse);
      expect(ClientSearchPolicy.shouldSearch('   '), isFalse);
    });

    test('rejects punctuation-only queries (nothing searchable)', () {
      expect(ClientSearchPolicy.shouldSearch('@'), isFalse);
      expect(ClientSearchPolicy.shouldSearch('---'), isFalse);
    });

    test('searches from the first character — single letters trigger it', () {
      expect(ClientSearchPolicy.shouldSearch('a'), isTrue);
      expect(ClientSearchPolicy.shouldSearch('é'), isTrue);
    });

    test('searches from the first digit — single digits trigger it', () {
      expect(ClientSearchPolicy.shouldSearch('5'), isTrue);
    });

    test('accepts longer text and phone queries', () {
      expect(ClientSearchPolicy.shouldSearch('ab'), isTrue);
      expect(ClientSearchPolicy.shouldSearch('Jo'), isTrue);
      expect(ClientSearchPolicy.shouldSearch('514'), isTrue);
      expect(ClientSearchPolicy.shouldSearch('5-14'), isTrue);
    });
  });

  group('ClientSearchPolicy.normalize', () {
    test('lowercases', () {
      expect(ClientSearchPolicy.normalize('ABC'), 'abc');
    });

    test('strips accents', () {
      expect(ClientSearchPolicy.normalize('Montréal'), 'montreal');
      expect(ClientSearchPolicy.normalize('Façade'), 'facade');
      // Accents are replaced character-for-character (no spacing between);
      // word-spacing comes from the final non-alphanumeric collapse step.
      expect(
        ClientSearchPolicy.normalize('àáâãäå èéêë ìíîï òóôõö ùúûü'),
        'aaaaaa eeee iiii ooooo uuuu',
      );
    });

    test('collapses non-alphanumerics to single spaces and trims', () {
      expect(ClientSearchPolicy.normalize('  Hello, World!  '), 'hello world');
      expect(ClientSearchPolicy.normalize('a---b'), 'a b');
    });
  });

  group('ClientSearchPolicy.digitsOnly', () {
    test('keeps only 0-9', () {
      expect(ClientSearchPolicy.digitsOnly('+1 (514) 555-0101'), '15145550101');
      expect(ClientSearchPolicy.digitsOnly('abc'), '');
    });
  });

  group('ClientSearchPolicy.cacheKey', () {
    test('two queries that normalize identically share a cache key', () {
      expect(
        ClientSearchPolicy.cacheKey('Montréal'),
        ClientSearchPolicy.cacheKey('  MONTREAL  '),
      );
    });
  });

  // These tests lock in the reshaped search fields (firstName, mobile) that
  // replaced the old businessName field in the client record.
  group('client list search filter (_matches)', () {
    const sophie = ClientRecord(
      id: 'c1',
      name: 'Tremblay Services',
      firstName: 'Sophie',
      lastName: 'Tremblay',
      mobile: '438-555-0199',
      email: 'sophie@tremblay.com',
    );

    test('firstName-only query matches the client', () {
      expect(_matches(sophie, 'Sophie'), isTrue);
    });

    test('partial firstName match (case-insensitive) matches the client', () {
      expect(_matches(sophie, 'soph'), isTrue);
    });

    test('mobile-only query matches the client', () {
      expect(_matches(sophie, '4385550199'), isTrue);
    });

    test('partial mobile digits match the client', () {
      expect(_matches(sophie, '5550199'), isTrue);
    });

    test('unrelated query does not match', () {
      expect(_matches(sophie, 'Xavier'), isFalse);
    });
  });
}
