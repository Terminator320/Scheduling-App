import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

void main() {
  group('ClientSearchPolicy.shouldSearch', () {
    test('rejects empty and whitespace queries', () {
      expect(ClientSearchPolicy.shouldSearch(''), isFalse);
      expect(ClientSearchPolicy.shouldSearch('   '), isFalse);
    });

    test('rejects single-letter text queries', () {
      expect(ClientSearchPolicy.shouldSearch('a'), isFalse);
      expect(ClientSearchPolicy.shouldSearch('é'), isFalse);
    });

    test('accepts two-letter text queries', () {
      expect(ClientSearchPolicy.shouldSearch('ab'), isTrue);
      expect(ClientSearchPolicy.shouldSearch('Jo'), isTrue);
    });

    test('accepts three-digit phone queries even when whole text is short', () {
      expect(ClientSearchPolicy.shouldSearch('514'), isTrue);
      expect(ClientSearchPolicy.shouldSearch('5-14'), isTrue);
    });

    test('rejects single-digit queries (fails both phone- and text-length gates)', () {
      expect(ClientSearchPolicy.shouldSearch('5'), isFalse);
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
