/// A bounded, TTL'd LRU of search results, keyed by normalized query.
class SearchResultCache<T> {
  SearchResultCache({
    required DateTime Function() clock,
    this.maxEntries = 50,
    this.ttl = const Duration(minutes: 2),
  }) : _clock = clock;

  final DateTime Function() _clock;

  /// Bound on retained queries, so a long-lived repository singleton cannot
  /// grow this without limit.
  final int maxEntries;

  /// How long a cached result stands.
  final Duration ttl;

  final Map<String, _CachedSearch<T>> _entries = {};

  /// Whether something stamped at [fetchedAt] is still inside [ttl].
  bool isFresh(DateTime fetchedAt) => _clock().difference(fetchedAt) < ttl;

  /// The cached results for [key], or null when absent or stale.
  List<T>? read(String key) {
    final cached = _entries[key];
    if (cached == null || !isFresh(cached.fetchedAt)) {
      _entries.remove(key);
      return null;
    }
    write(key, cached.results);
    return cached.results;
  }

  /// Stores [results] for [key], evicting the least recently used entry first.
  void write(String key, List<T> results) {
    _entries.remove(key);
    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = _CachedSearch(results, _clock());
  }

  /// Forgets every entry. Invalidation policy stays with the caller.
  void clear() => _entries.clear();

  /// Retained entry count, for tests that pin the eviction bound.
  int get length => _entries.length;
}

class _CachedSearch<T> {
  const _CachedSearch(this.results, this.fetchedAt);

  final List<T> results;
  final DateTime fetchedAt;
}
