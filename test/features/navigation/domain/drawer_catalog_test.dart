import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/features/navigation/domain/drawer_catalog.dart';

void main() {
  test('an admin sees eight rows in four groups', () {
    final groups = drawerGroups(isAdmin: true);
    expect(groups, hasLength(4));
    expect(groups.expand((g) => g.rows), hasLength(8)); // 10 once P5+P6 land
  });

  test('an employee sees only TODAY and ACCOUNT', () {
    final groups = drawerGroups(isAdmin: false);
    expect(groups, hasLength(2));
    final rows = groups.expand((g) => g.rows).toList();
    expect(rows, contains(HubTab.calendar));
    expect(rows, contains(PushedDestination.dayRoute));
    expect(rows, contains(PushedDestination.settings));
    expect(rows, isNot(contains(HubTab.clients)));
    expect(rows, isNot(contains(HubTab.employees)));
    expect(rows, isNot(contains(HubTab.liveMap)));
    expect(rows, isNot(contains(PushedDestination.dashboard)));
  });

  test('an employee reaches History from the TODAY group', () {
    // Their one search: the finished and cancelled jobs they were on. Under
    // TODAY because a technician has no BUSINESS group.
    final today = drawerGroups(isAdmin: false).first.rows;
    expect(today, contains(PushedDestination.history));
  });

  test('no destination appears in more than one group', () {
    for (final isAdmin in [true, false]) {
      final rows = drawerGroups(
        isAdmin: isAdmin,
      ).expand((g) => g.rows).toList();
      expect(rows.toSet().length, rows.length, reason: 'isAdmin=$isAdmin');
    }
  });

  test('every drawer row has a dot colour', () {
    for (final destination in drawerGroups(
      isAdmin: true,
    ).expand((g) => g.rows)) {
      expect(drawerDotColor(destination), isNotNull, reason: '$destination');
    }
  });

  test('every destination has a row icon', () {
    for (final destination in allDestinations) {
      expect(
        drawerRowIcon(destination),
        isA<IconData>(),
        reason: '$destination has no drawer icon',
      );
    }
  });

  test('no two destinations share an icon', () {
    // Colour is never the sole indicator of a row, so the icon has to carry
    // the row's identity on its own.
    final icons = [for (final d in allDestinations) drawerRowIcon(d)];
    expect(icons.toSet().length, icons.length);
  });

  test('no two destinations share a colour', () {
    final colors = [for (final d in allDestinations) drawerDotColor(d)];
    expect(colors.toSet().length, colors.length);
  });
}
