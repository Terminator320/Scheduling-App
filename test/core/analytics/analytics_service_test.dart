import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/analytics/analytics_events.dart';
import 'package:scheduling/core/analytics/analytics_service.dart';
import 'package:scheduling/core/logging/app_logger.dart';

/// Records what the service sends. `noSuchMethod` covers the rest of the
/// plugin's surface, which this app never touches.
class _FakeAnalytics implements FirebaseAnalytics {
  final List<({String name, Map<String, Object>? parameters})> events = [];
  final List<({String name, String? value})> userProperties = [];
  final List<String?> screenViews = [];
  bool? collectionEnabled;

  /// When set, every call throws it — the "plugin channel is broken" case.
  Exception? failWith;

  @override
  Future<void> logEvent({
    required String name,
    Map<String, Object>? parameters,
    List<AnalyticsEventItem>? items,
    AnalyticsCallOptions? callOptions,
  }) async {
    if (failWith != null) throw failWith!;
    events.add((name: name, parameters: parameters));
  }

  @override
  Future<void> logScreenView({
    String? screenClass,
    String? screenName,
    Map<String, Object>? parameters,
    AnalyticsCallOptions? callOptions,
  }) async {
    if (failWith != null) throw failWith!;
    screenViews.add(screenName);
  }

  @override
  Future<void> setUserProperty({
    required String name,
    required String? value,
    AnalyticsCallOptions? callOptions,
  }) async {
    if (failWith != null) throw failWith!;
    userProperties.add((name: name, value: value));
  }

  @override
  Future<void> setAnalyticsCollectionEnabled(bool enabled) async {
    if (failWith != null) throw failWith!;
    collectionEnabled = enabled;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeAnalytics fake;
  late AnalyticsService service;

  setUp(() {
    fake = _FakeAnalytics();
    service = AnalyticsService(analytics: fake, logger: AppLogger());
  });

  group('events', () {
    test('logs a declared event with its sanitized parameters', () {
      service.logAppointmentCreated(
        source: AnalyticsSources.calendar,
        repeat: 'none',
        assigneeCount: 2,
        hasPhotos: true,
        isPersonal: false,
        isAllDay: false,
        isDayOff: false,
        isMultiDay: true,
      );

      expect(fake.events, hasLength(1));
      final event = fake.events.single;
      expect(event.name, AnalyticsEvents.appointmentCreated);
      expect(event.parameters, {
        AnalyticsParams.source: 'calendar',
        AnalyticsParams.repeat: 'none',
        AnalyticsParams.assigneeCount: 2,
        AnalyticsParams.hasPhotos: 1,
        AnalyticsParams.isPersonal: 0,
        AnalyticsParams.isAllDay: 0,
        AnalyticsParams.isDayOff: 0,
        AnalyticsParams.isMultiDay: 1,
      });
    });

    test('sends null parameters rather than an empty map', () {
      // Firebase treats an empty map and no map differently in the console.
      service.logJobStarted();
      expect(fake.events.single.parameters, isNull);
    });

    test('a null optional parameter is dropped, not sent as a null', () {
      service.logFilterUsed(
        surface: AnalyticsSurfaces.history,
        filterName: 'year',
      );
      expect(fake.events.single.parameters, {
        AnalyticsParams.surface: 'history',
        AnalyticsParams.filterName: 'year',
      });
    });

    test('a search reports the query SHAPE and never the query', () {
      service.logSearchUsed(
        surface: AnalyticsSurfaces.clients,
        queryLength: 'Tremblay'.length,
      );
      final params = fake.events.single.parameters!;
      expect(params[AnalyticsParams.surface], 'clients');
      expect(params[AnalyticsParams.queryLength], 10);
      expect(params.values.whereType<String>(), isNot(contains('Tremblay')));
    });

    test('a photo count is bucketed, never exact past the small range', () {
      service.logPhotoAdded(surface: AnalyticsSurfaces.fieldRecord, count: 40);
      expect(fake.events.single.parameters![AnalyticsParams.photoCount], 50);
    });
  });

  group('screen views', () {
    test('logs the screen name it is given', () {
      service.logScreenView('calendar');
      expect(fake.screenViews, ['calendar']);
    });
  });

  group('user properties', () {
    test('sets a declared property', () {
      service.setUserRole('admin');
      expect(fake.userProperties.single, (name: 'user_role', value: 'admin'));
    });

    test('a null or empty role CLEARS the property', () {
      // Sign-out, and the bootstrap window a fresh sign-in passes through:
      // attributing either to the previous session's role is the failure this
      // prevents.
      service
        ..setUserRole(null)
        ..setUserRole('');
      expect(fake.userProperties, [
        (name: 'user_role', value: null),
        (name: 'user_role', value: null),
      ]);
    });

    test('setBuildEnv and setAppLocale write their own properties', () {
      service
        ..setBuildEnv(AnalyticsBuildEnvs.debug)
        ..setAppLocale('fr');
      expect(fake.userProperties, [
        (name: 'build_env', value: 'debug'),
        (name: 'app_locale', value: 'fr'),
      ]);
    });

    test('setCollectionEnabled reaches the plugin', () {
      service.setCollectionEnabled(enabled: false);
      expect(fake.collectionEnabled, isFalse);
    });
  });

  group('failure containment', () {
    test('a throwing plugin does not propagate out of any method', () async {
      // The whole contract: analytics is instrumentation and must never be the
      // reason a save fails or a sheet crashes.
      fake.failWith = Exception('channel is dead');

      expect(service.logJobStarted, returnsNormally);
      expect(() => service.logScreenView('calendar'), returnsNormally);
      expect(() => service.setUserRole('admin'), returnsNormally);
      expect(
        () => service.setCollectionEnabled(enabled: true),
        returnsNormally,
      );

      // The failure is asynchronous inside the guard, so let it settle and
      // confirm nothing reached the zone as an unhandled error.
      await Future<void>.delayed(Duration.zero);
      expect(fake.events, isEmpty);
    });

    test('no event is recorded when the plugin is broken', () async {
      fake.failWith = Exception('boom');
      service.logClientEdited();
      await Future<void>.delayed(Duration.zero);
      expect(fake.events, isEmpty);
    });
  });

  test(
    'a service with no override and no Firebase is a silent no-op',
    () async {
      // Firebase is not initialized in a widget test. Resolving in the
      // constructor would make merely READING the provider throw, so every
      // instrumented widget would need an override to stay testable.
      final noFirebase = AnalyticsService(logger: AppLogger());
      expect(noFirebase.logJobStarted, returnsNormally);
      expect(() => noFirebase.logScreenView('calendar'), returnsNormally);
      await Future<void>.delayed(Duration.zero);
    },
  );
}
