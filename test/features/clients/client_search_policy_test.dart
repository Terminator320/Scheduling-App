import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

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
}
