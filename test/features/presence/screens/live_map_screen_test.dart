import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/maps/application/maps_providers.dart';
import 'package:scheduling/features/presence/application/live_map_providers.dart';
import 'package:scheduling/features/presence/domain/models/presence_fix.dart';
import 'package:scheduling/features/presence/screens/live_map_screen.dart';
import 'package:scheduling/l10n/l10n.dart';

final _now = DateTime(2026, 7, 17, 12);

const _alice = EmployeeRecord(id: 'u1', name: 'Alice', status: 'active');
const _bob = EmployeeRecord(id: 'u2', name: 'Bob', status: 'active');

PresenceFix _fix(String id, double lat, double lng, DateTime updatedAt) =>
    PresenceFix(userDocId: id, lat: lat, lng: lng, updatedAt: updatedAt);

void main() {
  late LiveMapConfig? lastConfig;

  setUp(() => lastConfig = null);

  Widget stubMap(LiveMapConfig config) {
    lastConfig = config;
    return const ColoredBox(color: Color(0xFF888888));
  }

  Widget themed(Widget child) => ThemeNotifier(
    themeMode: ThemeMode.light,
    toggleTheme: () {},
    textScale: 1,
    setTextScale: (_) {},
    setLanguage: (_) {},
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: lightTheme(),
      home: child,
    ),
  );

  Widget wrap({
    required List<Override> overrides,
    Widget child = const LiveMapScreen(isAdmin: true, employeeId: 'e1'),
  }) => ProviderScope(overrides: overrides, child: themed(child));

  // Marker icons encode via real dart:ui async that the fake test clock won't advance — drive under runAsync.
  Future<void> settleMap(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    });
    await tester.pump();
  }

  List<Override> baseOverrides({
    required Stream<List<PresenceFix>> presence,
    List<EmployeeRecord> users = const [_alice, _bob],
    StreamController<int>? tick,
    List<Override> extra = const [],
  }) => [
    allPresenceStreamProvider.overrideWith((ref) => presence),
    allUsersStreamProvider.overrideWith((ref) => Stream.value(users)),
    liveMapClockProvider.overrideWith(
      (ref) =>
          () => _now,
    ),
    liveMapTickProvider.overrideWith(
      (ref) => tick?.stream ?? const Stream<int>.empty(),
    ),
    ...extra,
  ];

  testWidgets('builds a marker per active staff member (incl. a stale one)', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        overrides: baseOverrides(
          presence: Stream.value([
            _fix('u1', 45.5, -73.6, _now),
            _fix('u2', 45.6, -73.7, _now.subtract(const Duration(minutes: 40))),
          ]),
        ),
        child: LiveMapScreen(
          isAdmin: true,
          employeeId: 'e1',
          mapBuilder: stubMap,
        ),
      ),
    );
    await settleMap(tester);

    expect(lastConfig, isNotNull);
    expect(lastConfig!.markers, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a marker shows the info card with name, freshness, '
      'and the resolved address', (tester) async {
    final key = ReverseGeocodeQuery(lat: 45.5, lng: -73.6, locale: 'en');
    await tester.pumpWidget(
      wrap(
        overrides: baseOverrides(
          presence: Stream.value([_fix('u1', 45.5, -73.6, _now)]),
          users: const [_alice],
          extra: [
            reverseGeocodeProvider(
              key,
            ).overrideWith((ref) async => '123 Alice St'),
          ],
        ),
        child: LiveMapScreen(
          isAdmin: true,
          employeeId: 'e1',
          mapBuilder: stubMap,
        ),
      ),
    );
    await settleMap(tester);

    final marker = lastConfig!.markers.firstWhere(
      (m) => m.markerId.value == 'u1',
    );
    marker.onTap!();
    await settleMap(tester);

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Just now'), findsOneWidget);
    expect(find.text('123 Alice St'), findsOneWidget);
  });

  testWidgets(
    'the address line is hidden when no address is available '
    '(same branch as a lookup failure)',
    (tester) async {
      final key = ReverseGeocodeQuery(lat: 45.5, lng: -73.6, locale: 'en');
      await tester.pumpWidget(
        wrap(
          overrides: baseOverrides(
            presence: Stream.value([_fix('u1', 45.5, -73.6, _now)]),
            users: const [_alice],
            // A null result (no address / lookup failure) takes the same
            // `SizedBox.shrink()` branch in the info card.
            extra: [
              reverseGeocodeProvider(key).overrideWith((ref) async => null),
            ],
          ),
          child: LiveMapScreen(
            isAdmin: true,
            employeeId: 'e1',
            mapBuilder: stubMap,
          ),
        ),
      );
      await settleMap(tester);

      lastConfig!.markers.first.onTap!();
      await settleMap(tester);

      // Card still shows the person, but no address / resolving line.
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Finding address…'), findsNothing);
      expect(find.text('123 Alice St'), findsNothing);
    },
  );

  testWidgets('empty presence data renders the empty-state card over the map', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        overrides: baseOverrides(
          presence: Stream.value(const []),
          users: const [_alice],
        ),
        child: LiveMapScreen(
          isAdmin: true,
          employeeId: 'e1',
          mapBuilder: stubMap,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(lastConfig, isNotNull, reason: 'map still renders when empty');
    expect(
      find.text('No one is sharing their location right now'),
      findsOneWidget,
    );
  });

  testWidgets('a presence stream error renders the error body', (tester) async {
    await tester.pumpWidget(
      wrap(
        overrides: baseOverrides(
          presence: Stream<List<PresenceFix>>.error(Exception('denied')),
          users: const [_alice],
        ),
        child: LiveMapScreen(
          isAdmin: true,
          employeeId: 'e1',
          mapBuilder: stubMap,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load the staff map"), findsOneWidget);
    expect(lastConfig, isNull, reason: 'no map is built in the error state');
  });

  testWidgets(
    'pauses the presence stream while the tab is hidden and re-attaches when '
    'it becomes visible',
    (tester) async {
      final presence = StreamController<List<PresenceFix>>.broadcast();
      addTearDown(presence.close);

      late StateSetter setOuter;
      // The hub wraps each tab in TickerMode(enabled: tab == current); mirror
      // that so a hidden tab (enabled: false) detaches its data watches.
      var visible = false;

      await tester.pumpWidget(
        wrap(
          overrides: baseOverrides(presence: presence.stream),
          child: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return TickerMode(
                enabled: visible,
                child: LiveMapScreen(
                  isAdmin: true,
                  employeeId: 'e1',
                  mapBuilder: stubMap,
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      expect(
        presence.hasListener,
        isFalse,
        reason: 'hidden tab must not watch the presence stream',
      );

      setOuter(() => visible = true);
      await tester.pump();
      await tester.pump();

      expect(
        presence.hasListener,
        isTrue,
        reason: 'becoming visible re-attaches the presence stream',
      );
    },
  );
}
