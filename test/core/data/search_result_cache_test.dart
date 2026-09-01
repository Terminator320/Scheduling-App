import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/data/search_result_cache.dart';

/// The LRU behind both repositories' search caches.
///
/// It was implemented twice — byte-identical `_isFresh`/`_cacheSearch` over
/// identical dials — and NEITHER copy had a test for expiry or eviction: the
/// injected clock existed so they could, and `clock:` appeared in zero calendar
/// test files. Only invalidation was ever pinned. Extracting the class is what
/// makes the eviction observable at all; through a repository it is not, since
/// a hit and a recompute return the same answer.
void main() {
  late DateTime now;
  SearchResultCache<String> cache({int maxEntries = 50}) =>
      SearchResultCache(clock: () => now, maxEntries: maxEntries);

  setUp(() => now = DateTime(2026, 9, 1, 12));

  group('TTL', () {
    test('a read inside the window returns the stored results', () {
      final c = cache()..write('q', ['a']);
      now = now.add(const Duration(seconds: 119));

      expect(c.read('q'), ['a']);
    });

    test('a read past the window misses', () {
      final c = cache()..write('q', ['a']);
      now = now.add(const Duration(seconds: 121));

      expect(c.read('q'), isNull);
    });

    test('a stale entry is DROPPED, not merely reported missing', () {
      // Otherwise an expired key still occupies an LRU slot, and a surface
      // searching a rotating set of terms evicts live entries to hold dead
      // ones.
      final c = cache()..write('q', ['a']);
      now = now.add(const Duration(seconds: 121));
      c.read('q');

      expect(c.length, 0);
    });

    test('isFresh is the same rule the scan windows use', () {
      final c = cache();
      expect(c.isFresh(now), isTrue);
      expect(c.isFresh(now.subtract(const Duration(seconds: 119))), isTrue);
      expect(c.isFresh(now.subtract(const Duration(seconds: 121))), isFalse);
    });
  });

  group('eviction', () {
    test('the map never grows past maxEntries', () {
      final c = cache(maxEntries: 3);
      for (var i = 0; i < 10; i++) {
        c.write('q$i', ['r$i']);
      }

      expect(c.length, 3);
    });

    test('the OLDEST entry goes first', () {
      final c = cache(maxEntries: 3)
        ..write('a', ['1'])
        ..write('b', ['2'])
        ..write('c', ['3'])
        ..write('d', ['4']);

      expect(c.read('a'), isNull);
      expect(c.read('d'), ['4']);
    });

    test('a READ refreshes recency, so this is an LRU not a queue', () {
      // The re-insert on a hit is the only thing making this true, and it
      // looked like a redundant line in both copies.
      final c = cache(maxEntries: 3)
        ..write('a', ['1'])
        ..write('b', ['2'])
        ..write('c', ['3'])
        ..read('a')
        ..write('d', ['4']);

      expect(c.read('a'), ['1'], reason: 'refreshed by the read above');
      expect(c.read('b'), isNull, reason: 'now the least recently used');
    });

    test('rewriting a key does not consume a second slot', () {
      final c = cache(maxEntries: 2)
        ..write('a', ['1'])
        ..write('a', ['2'])
        ..write('b', ['3']);

      expect(c.length, 2);
      expect(c.read('a'), ['2']);
      expect(c.read('b'), ['3']);
    });
  });

  test('clear forgets everything', () {
    final c = cache()
      ..write('a', ['1'])
      ..write('b', ['2'])
      ..clear();

    expect(c.length, 0);
    expect(c.read('a'), isNull);
  });
}
