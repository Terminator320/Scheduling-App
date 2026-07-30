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
    final rows = groups.expand((g) => g.rows).toList();
    expect(rows, contains(HubTab.calendar));
    expect(rows, contains(PushedDestination.dayRoute));
    expect(rows, contains(PushedDestination.settings));
    expect(rows, isNot(contains(HubTab.clients)));
    expect(rows, isNot(contains(HubTab.employees)));
    expect(rows, isNot(contains(HubTab.liveMap)));
    expect(rows, isNot(contains(PushedDestination.dashboard)));
    expect(rows, isNot(contains(PushedDestination.history)));
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
}
