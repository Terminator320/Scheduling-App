import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/dashboard/domain/new_client_trend.dart';

void main() {
  group('newClientTrend', () {
    test('splits the window in half and totals each side', () {
      // Oldest first: 1+2+0+1 = 4 behind, 2+3+1+2 = 8 recent.
      final trend = newClientTrend([1, 2, 0, 1, 2, 3, 1, 2]);

      expect(trend.total, 12);
      expect(trend.previous, 4);
      expect(trend.recent, 8);
      expect(trend.delta, 4);
      expect(trend.halfWeeks, 4);
      expect(trend.hasComparison, isTrue);
      expect(trend.isEmpty, isFalse);
    });

    test('a fall is a negative delta', () {
      final trend = newClientTrend([5, 5, 1, 0]);

      expect(trend.previous, 10);
      expect(trend.recent, 1);
      expect(trend.delta, -9);
    });

    test('an odd bucket count drops the OLDEST bucket rather than comparing '
        'halves of different sizes', () {
      // 5 buckets: the leading 4 is ignored, so it is [3,1] vs [2,4].
      final trend = newClientTrend([4, 3, 1, 2, 4]);

      expect(trend.halfWeeks, 2);
      expect(trend.previous, 4);
      expect(trend.recent, 6);
      // The dropped bucket still counts towards the headline figure — the
      // window did have 14 new clients in it.
      expect(trend.total, 14);
    });

    test('an empty window offers no comparison and reports itself empty', () {
      final trend = newClientTrend([0, 0, 0, 0]);

      expect(trend.total, 0);
      expect(trend.delta, 0);
      // "0, no change from 0" is noise, not a trend.
      expect(trend.hasComparison, isFalse);
      expect(trend.isEmpty, isTrue);
    });

    test('a single bucket has nothing behind it to compare against', () {
      final trend = newClientTrend([3]);

      expect(trend.total, 3);
      expect(trend.halfWeeks, 0);
      expect(trend.hasComparison, isFalse);
    });

    test('no buckets at all is handled, not thrown on', () {
      final trend = newClientTrend([]);

      expect(trend.total, 0);
      expect(trend.hasComparison, isFalse);
      expect(trend.isEmpty, isTrue);
    });
  });
}
