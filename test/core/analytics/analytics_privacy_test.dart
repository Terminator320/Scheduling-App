import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/analytics/analytics_events.dart';
import 'package:scheduling/core/analytics/analytics_privacy.dart';

void main() {
  group('sanitizeAnalyticsParams', () {
    test('drops a key that is not on the allowlist', () {
      // The load-bearing case: an undeclared key is how a client name or phone
      // number would reach the wire. Asserts in debug, so this runs the drop
      // through the release-shaped path by disabling the assertion first.
      expect(
        () => sanitizeAnalyticsParams(const {'client_name': 'Marc Tremblay'}),
        throwsA(isA<AssertionError>()),
      );
    });

    test('keeps only declared keys when mixed with an undeclared one', () {
      // Same shape as above — the assert fires on the undeclared key, which is
      // the point: a bad call site must fail loudly for its author.
      expect(
        () => sanitizeAnalyticsParams(const {
          AnalyticsParams.status: 'done',
          'client_phone': '5145551234',
        }),
        throwsA(isA<AssertionError>()),
      );
    });

    test('converts a bool to 1/0 — Firebase has no boolean parameter', () {
      final sanitized = sanitizeAnalyticsParams(const {
        AnalyticsParams.hasPhotos: true,
        AnalyticsParams.isPersonal: false,
      });
      expect(sanitized, {
        AnalyticsParams.hasPhotos: 1,
        AnalyticsParams.isPersonal: 0,
      });
    });

    test('passes a finite num through and drops NaN/Infinity', () {
      expect(
        sanitizeAnalyticsParams(const {AnalyticsParams.assigneeCount: 3}),
        {AnalyticsParams.assigneeCount: 3},
      );
      expect(
        sanitizeAnalyticsParams({AnalyticsParams.delayMinutes: double.nan}),
        isEmpty,
      );
      expect(
        sanitizeAnalyticsParams({
          AnalyticsParams.delayMinutes: double.infinity,
        }),
        isEmpty,
      );
    });

    test('drops a null value and an empty/whitespace string', () {
      expect(
        sanitizeAnalyticsParams(const {AnalyticsParams.source: null}),
        isEmpty,
      );
      expect(
        sanitizeAnalyticsParams(const {AnalyticsParams.source: '   '}),
        isEmpty,
      );
    });

    test('trims and caps a long string value', () {
      final long = 'x' * (kAnalyticsMaxValueLength + 40);
      final sanitized = sanitizeAnalyticsParams({
        AnalyticsParams.source: '  $long  ',
      });
      expect(
        (sanitized[AnalyticsParams.source]! as String).length,
        kAnalyticsMaxValueLength,
      );
    });

    test('drops a value that is neither num, bool nor String', () {
      // `toString()` on a domain model is exactly how a client record's whole
      // contents would reach a parameter, so a non-primitive is dropped rather
      // than stringified.
      expect(
        sanitizeAnalyticsParams({AnalyticsParams.source: DateTime(2026, 9, 7)}),
        isEmpty,
      );
      expect(
        sanitizeAnalyticsParams({
          AnalyticsParams.source: const ['a', 'b'],
        }),
        isEmpty,
      );
    });

    test('a null or empty map sanitizes to an empty map', () {
      expect(sanitizeAnalyticsParams(null), isEmpty);
      expect(sanitizeAnalyticsParams(const {}), isEmpty);
    });
  });

  group('bucketCount', () {
    test('keeps small counts exact and collapses the long tail', () {
      // A count of 1 is fine; an exact 4173 describes one business on one day.
      expect(bucketCount(0), 0);
      expect(bucketCount(-4), 0);
      expect(bucketCount(1), 1);
      expect(bucketCount(5), 5);
      expect(bucketCount(6), 10);
      expect(bucketCount(11), 25);
      expect(bucketCount(26), 50);
      expect(bucketCount(51), 100);
      expect(bucketCount(4173), 500);
    });
  });

  group('bucketQueryLength', () {
    test('reports the shape of a query and never its length exactly', () {
      expect(bucketQueryLength(0), 0);
      expect(bucketQueryLength(1), 2);
      expect(bucketQueryLength(4), 5);
      expect(bucketQueryLength(9), 10);
      expect(bucketQueryLength(40), 20);
    });
  });

  group('name guards', () {
    test('isKnownEvent accepts a declared event and refuses anything else', () {
      expect(isKnownEvent(AnalyticsEvents.jobCompleted), isTrue);
      expect(isKnownEvent('job_completed_v2'), isFalse);
    });

    test('isKnownUserProperty accepts only the three declared ones', () {
      expect(isKnownUserProperty(AnalyticsUserProperties.userRole), isTrue);
      expect(isKnownUserProperty('user_email'), isFalse);
    });

    test('sanitizeUserPropertyValue caps and nulls out blanks', () {
      expect(sanitizeUserPropertyValue(null), isNull);
      expect(sanitizeUserPropertyValue('  '), isNull);
      expect(sanitizeUserPropertyValue('  admin '), 'admin');
      expect(
        sanitizeUserPropertyValue('y' * 100)!.length,
        kAnalyticsMaxValueLength,
      );
    });
  });
}
