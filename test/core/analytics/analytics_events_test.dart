import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/analytics/analytics_events.dart';

/// Firebase drops a malformed name SILENTLY — the event simply never appears in
/// the console — so the vocabulary is checked here rather than discovered in
/// production three weeks into a reporting window.
void main() {
  group('event names', () {
    test('every declared event is well formed', () {
      for (final name in AnalyticsEvents.allEvents) {
        expect(
          AnalyticsNames.isValidEvent(name),
          isTrue,
          reason: '"$name" is not a valid Firebase event name',
        );
      }
    });

    test('no event uses a reserved prefix', () {
      for (final name in AnalyticsEvents.allEvents) {
        expect(name.startsWith('firebase_'), isFalse, reason: name);
        expect(name.startsWith('google_'), isFalse, reason: name);
        expect(name.startsWith('ga_'), isFalse, reason: name);
      }
    });

    test('the declared set has no duplicates and is non-empty', () {
      expect(AnalyticsEvents.allEvents, isNotEmpty);
      expect(
        AnalyticsEvents.allEvents.length,
        AnalyticsEvents.allEvents.toSet().length,
      );
    });

    test('a name over the 40-char cap is rejected', () {
      expect(AnalyticsNames.isValidEvent('a' * 41), isFalse);
      expect(AnalyticsNames.isValidEvent('a' * 40), isTrue);
    });

    test('a name that does not start with a letter is rejected', () {
      expect(AnalyticsNames.isValidEvent('1job'), isFalse);
      expect(AnalyticsNames.isValidEvent('_job'), isFalse);
      expect(AnalyticsNames.isValidEvent('job-completed'), isFalse);
      expect(AnalyticsNames.isValidEvent(''), isFalse);
    });
  });

  group('parameter names', () {
    test('every declared parameter is well formed', () {
      for (final name in AnalyticsParams.allParams) {
        expect(
          AnalyticsNames.isValidParam(name),
          isTrue,
          reason: '"$name" is not a valid Firebase parameter name',
        );
      }
    });

    test('the allowlist has no duplicates', () {
      expect(
        AnalyticsParams.allParams.length,
        AnalyticsParams.allParams.toSet().length,
      );
    });
  });

  group('user properties', () {
    test('every declared property is well formed', () {
      for (final name in AnalyticsUserProperties.allProperties) {
        expect(
          AnalyticsNames.isValidUserProperty(name),
          isTrue,
          reason: '"$name" is not a valid Firebase user property name',
        );
      }
    });

    test('the 24-char user-property cap is shorter than the event cap', () {
      // Firebase's own limits differ; a name valid as an event can be too long
      // as a user property, which is the mistake this guards.
      expect(AnalyticsNames.isValidUserProperty('a' * 25), isFalse);
      expect(AnalyticsNames.isValidUserProperty('a' * 24), isTrue);
      expect(AnalyticsNames.isValidEvent('a' * 25), isTrue);
    });

    test('Firebase allows 25 properties per project and we are well under', () {
      expect(
        AnalyticsUserProperties.allProperties.length,
        lessThanOrEqualTo(25),
      );
    });

    test('no property name suggests it carries an identity', () {
      // A guard on the shape of the vocabulary, not on a value: nothing here
      // may be a uid, an email or a name.
      const forbidden = ['uid', 'user_id', 'email', 'name', 'phone'];
      for (final name in AnalyticsUserProperties.allProperties) {
        expect(forbidden, isNot(contains(name)), reason: name);
      }
    });
  });
}
