import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/navigation/app_destination.dart';

void main() {
  test('there are exactly four hub tabs', () {
    expect(HubTab.values, hasLength(4));
  });

  test('destination names are unique across both enums', () {
    // The names are also SharedPreferences seen-keys AND showcase scope
    // names, so a collision would be two silent bugs at once.
    final names = [for (final d in allDestinations) d.name];
    expect(names.toSet().length, names.length);
  });

  test('every destination resolves to a route', () {
    for (final destination in allDestinations) {
      final target = destinationRoute(
        destination,
        isAdmin: true,
        employeeId: 'e1',
      );
      expect(target.route, isNotEmpty);
    }
  });
}
