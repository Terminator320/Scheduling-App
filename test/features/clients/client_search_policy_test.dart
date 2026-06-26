import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

// The clients list filters its loaded pages through this exact policy method,
// so these tests exercise the real matcher (no hand-copied mirror to drift).
bool _matches(ClientRecord c, String query) =>
    ClientSearchPolicy.matchesClient(c, query);

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

    test('searches from the first character; single letters trigger it', () {
      expect(ClientSearchPolicy.shouldSearch('a'), isTrue);
      expect(ClientSearchPolicy.shouldSearch('\u00E9'), isTrue);
    });

    test('searches from the first digit; single digits trigger it', () {
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
      expect(ClientSearchPolicy.normalize('Montr\u00E9al'), 'montreal');
      expect(ClientSearchPolicy.normalize('Fa\u00E7ade'), 'facade');
      expect(
        ClientSearchPolicy.normalize(
          '\u00E0\u00E1\u00E2\u00E3\u00E4\u00E5 '
          '\u00E8\u00E9\u00EA\u00EB '
          '\u00EC\u00ED\u00EE\u00EF '
          '\u00F2\u00F3\u00F4\u00F5\u00F6 '
          '\u00F9\u00FA\u00FB\u00FC',
        ),
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
        ClientSearchPolicy.cacheKey('Montr\u00E9al'),
        ClientSearchPolicy.cacheKey('  MONTREAL  '),
      );
    });
  });

  group('ClientSearchPolicy.matchesClient', () {
    const sophie = ClientRecord(
      id: 'c1',
      name: 'Tremblay Services',
      firstName: 'Sophie',
      lastName: 'Tremblay',
      address: '123 Rue Sainte-Catherine',
      city: 'Montr\u00E9al',
      mobile: '438-555-0199',
      email: 'sophie@tremblay.com',
      contacts: [
        ClientContact(
          name: 'Marc Lefebvre',
          phone: '514-555-7777',
          email: 'marc@lefebvre.ca',
        ),
      ],
    );

    test('firstName-only query matches the client', () {
      expect(_matches(sophie, 'Sophie'), isTrue);
    });

    test('partial firstName match (case-insensitive) matches the client', () {
      expect(_matches(sophie, 'soph'), isTrue);
    });

    test('business/display name matches the client', () {
      expect(_matches(sophie, 'Tremblay Services'), isTrue);
    });

    test('email query matches the client', () {
      expect(_matches(sophie, 'sophie@tremblay.com'), isTrue);
    });

    test('address query matches the client', () {
      expect(_matches(sophie, 'Sainte-Catherine'), isTrue);
    });

    test('accent-insensitive city query matches the client', () {
      expect(_matches(sophie, 'montreal'), isTrue);
    });

    test('contact name matches the client', () {
      expect(_matches(sophie, 'Lefebvre'), isTrue);
    });

    test('contact email matches the client', () {
      expect(_matches(sophie, 'marc@lefebvre.ca'), isTrue);
    });

    test('contact phone digits match the client', () {
      expect(_matches(sophie, '5145557777'), isTrue);
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

    test('blank query does not match', () {
      expect(_matches(sophie, '   '), isFalse);
    });
  });
}
