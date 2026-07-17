import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/presence/domain/live_map_aggregator.dart';
import 'package:scheduling/features/presence/domain/models/presence_fix.dart';

void main() {
  final now = DateTime(2026, 7, 17, 12);

  EmployeeRecord user({
    required String id,
    String name = 'A',
    Color color = Colors.red,
    String status = 'active',
  }) => EmployeeRecord(id: id, name: name, color: color, status: status);

  group('LiveMapAggregator.join', () {
    test('carries name and color from the matching user', () {
      final points = LiveMapAggregator.join(
        fixes: [
          const PresenceFix(
            userDocId: 'u1',
            lat: 45.5,
            lng: -73.6,
            updatedAt: null,
          ),
        ],
        users: [user(id: 'u1', name: 'Alice', color: Colors.blue)],
      );

      expect(points, hasLength(1));
      expect(points.single.name, 'Alice');
      expect(points.single.color, Colors.blue);
      expect(points.single.lat, 45.5);
      expect(points.single.lng, -73.6);
    });

    test('drops a fix with no matching user', () {
      final points = LiveMapAggregator.join(
        fixes: [
          const PresenceFix(
            userDocId: 'ghost',
            lat: 1,
            lng: 2,
            updatedAt: null,
          ),
        ],
        users: [user(id: 'u1')],
      );

      expect(points, isEmpty);
    });

    test('drops fixes for disabled or invited users', () {
      final points = LiveMapAggregator.join(
        fixes: [
          const PresenceFix(
            userDocId: 'disabled',
            lat: 1,
            lng: 2,
            updatedAt: null,
          ),
          const PresenceFix(
            userDocId: 'invited',
            lat: 3,
            lng: 4,
            updatedAt: null,
          ),
        ],
        users: [
          user(id: 'disabled', status: 'disabled'),
          user(id: 'invited', status: 'invited'),
        ],
      );

      expect(points, isEmpty);
    });

    test('result is sorted by name', () {
      final points = LiveMapAggregator.join(
        fixes: [
          const PresenceFix(userDocId: 'z', lat: 1, lng: 1, updatedAt: null),
          const PresenceFix(userDocId: 'a', lat: 2, lng: 2, updatedAt: null),
          const PresenceFix(userDocId: 'm', lat: 3, lng: 3, updatedAt: null),
        ],
        users: [
          user(id: 'z', name: 'Zack'),
          user(id: 'a', name: 'Amy'),
          user(id: 'm', name: 'Max'),
        ],
      );

      expect(points.map((p) => p.name), ['Amy', 'Max', 'Zack']);
    });
  });

  group('LiveMapAggregator.isStale', () {
    test('null updatedAt is fresh', () {
      expect(LiveMapAggregator.isStale(null, now), isFalse);
    });

    test('24m59s is fresh', () {
      final updatedAt = now.subtract(const Duration(minutes: 24, seconds: 59));
      expect(LiveMapAggregator.isStale(updatedAt, now), isFalse);
    });

    test('exactly 25m00s is NOT stale (strict >)', () {
      final updatedAt = now.subtract(const Duration(minutes: 25));
      expect(LiveMapAggregator.isStale(updatedAt, now), isFalse);
    });

    test('25m01s is stale', () {
      final updatedAt = now.subtract(const Duration(minutes: 25, seconds: 1));
      expect(LiveMapAggregator.isStale(updatedAt, now), isTrue);
    });
  });

  group('LiveMapAggregator.freshnessOf', () {
    test('null updatedAt is justNow', () {
      expect(
        LiveMapAggregator.freshnessOf(null, now),
        isA<FreshnessJustNow>(),
      );
    });

    test('under 60s is justNow', () {
      final updatedAt = now.subtract(const Duration(seconds: 30));
      expect(
        LiveMapAggregator.freshnessOf(updatedAt, now),
        isA<FreshnessJustNow>(),
      );
    });

    test('1-59 minutes buckets as minutesAgo', () {
      final updatedAt = now.subtract(const Duration(minutes: 5));
      final bucket = LiveMapAggregator.freshnessOf(updatedAt, now);
      expect(bucket, isA<FreshnessMinutesAgo>());
      expect((bucket as FreshnessMinutesAgo).minutes, 5);
    });

    test('60+ minutes buckets as hoursAgo', () {
      final updatedAt = now.subtract(const Duration(hours: 3));
      final bucket = LiveMapAggregator.freshnessOf(updatedAt, now);
      expect(bucket, isA<FreshnessHoursAgo>());
      expect((bucket as FreshnessHoursAgo).hours, 3);
    });
  });
}
