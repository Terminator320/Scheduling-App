import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/search/search_tokens.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

// The worked examples here are shared, value for value, with
// `functions/__tests__/search_tokens.test.js`. This tokenizer is hand-mirrored
// in JS: the app writes the tokens and the server queries them, so a
// divergence is a search that silently returns nothing.
void main() {
  group('searchQueryTokens', () {
    test('emits one whole-word token per word plus the full digit run', () {
      expect(searchQueryTokens('Marc 514'), [
        't:marc',
        't:514',
        'p:514',
      ]);
    });

    test('is empty for a query with nothing searchable in it', () {
      expect(searchQueryTokens('  --  '), isEmpty);
    });

    test('never sends more than the query limit', () {
      final tokens = searchQueryTokens('a b c d e f g h i j k l m');
      expect(tokens.length, kSearchTokenQueryLimit);
    });
  });

  group('searchIndexTokens', () {
    test('emits each whole word before any of its prefixes', () {
      final tokens = searchIndexTokens(texts: ['Marc'], phones: const []);
      expect(tokens, ['t:marc', 't:m', 't:ma', 't:mar']);
    });

    test('interleaves phones so a long name cannot starve them out', () {
      // The exact list the JS twin asserts. Before the interleave the first
      // ten were all name prefixes and the phone was never indexed at all.
      expect(
        searchIndexTokens(
          texts: ['Marc Tremblay'],
          phones: ['(514) 555-4321'],
          limit: 10,
        ),
        [
          't:marc',
          'p:5145554321',
          't:m',
          'p:514',
          't:ma',
          'p:5145',
          't:mar',
          'p:51455',
          't:tremblay',
          'p:514555',
        ],
      );
    });

    test('a whole word and the whole number survive the tightest budget', () {
      final tokens = searchIndexTokens(
        texts: ['Tremblay'],
        phones: ['5145554321'],
        limit: 2,
      );
      expect(tokens, ['t:tremblay', 'p:5145554321']);
    });

    test('accent folding makes an accented name reachable unaccented', () {
      expect(
        searchIndexTokens(texts: ['Éric'], phones: const []),
        contains('t:eric'),
      );
    });

    test('a run shorter than three digits is not indexed', () {
      expect(searchIndexTokens(texts: const [], phones: ['12']), isEmpty);
    });

    test('honours the field cap', () {
      final tokens = searchIndexTokens(
        texts: [for (var i = 0; i < 200; i++) 'word$i'],
        phones: ['5145554321'],
      );
      expect(tokens.length, kSearchTokenFieldLimit);
    });
  });

  group('accent folding parity with functions/search_tokens.js', () {
    // These four are the shared worked examples. The app writes the index with
    // this fold and the server tokenizes the typed query with its own; a
    // character they disagree about is a record nobody can find.
    test('folds the Latin-1 letters the JS mirror folds', () {
      expect(ClientSearchPolicy.normalize('Muñoz'), 'munoz');
      expect(ClientSearchPolicy.normalize('Éric Tremblay'), 'eric tremblay');
      expect(ClientSearchPolicy.normalize('Ångström'), 'angstrom');
    });

    test('a letter outside the table is a separator on both sides', () {
      expect(ClientSearchPolicy.normalize('Šarko'), 'arko');
    });
  });
}
