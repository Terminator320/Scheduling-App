/// A bounded, TTL'd LRU of search results, keyed by normalized query.
///
/// **One owner for two dials that are one decision.** The clients and
/// appointments repositories each carried a byte-identical `_isFresh` /
/// `_cacheSearch` pair over an identical `_searchCacheMax` (50) and a 2-minute
/// TTL — the same precedent as `kSearchDebounce` ("one cost dial, not a
/// per-surface taste") and as `pageToCap`, which exists because four
/// hand-written paging loops were four chances to omit the cap.
///
/// Deliberately does NOT own invalidation. The two repositories legitimately
/// differ there: the appointments one patches a scan window and pokes
/// `_localWrites`, the clients one patches its own window, and the sign-out
/// path clears without waking any listener. `clear()` is the primitive they
/// build on.
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

  /// How long a cached result stands. It is a safety net for REMOTE writes;
  /// local writes are expected to invalidate or patch explicitly.
  final Duration ttl;

  final Map<String, _CachedSearch<T>> _entries = {};

  /// Whether something stamped at [fetchedAt] is still inside [ttl].
  ///
  /// Exposed because both repositories apply the same freshness rule to their
  /// scan WINDOW as well as to these entries, and two clocks answering that
  /// question differently is exactly the drift this class removes.
  bool isFresh(DateTime fetchedAt) => _clock().difference(fetchedAt) < ttl;

  /// The cached results for [key], or null when absent or stale.
  ///
  /// A hit refreshes recency, which is what makes the eviction below an LRU
  /// rather than an insertion-order queue.
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
