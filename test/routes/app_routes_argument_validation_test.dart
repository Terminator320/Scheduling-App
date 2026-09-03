import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/routes/app_routes.dart';

void main() {
  test('argument-required routes recover instead of throwing', () {
    for (final routeName in const [
      AppRoutes.dayRoute,
      AppRoutes.mainCalendar,
      AppRoutes.employees,
      AppRoutes.clients,
      AppRoutes.history,
      AppRoutes.liveMap,
      AppRoutes.settings,
    ]) {
      final route = AppRoutes.onGenerateRoute(RouteSettings(name: routeName));

      expect(route, isA<MaterialPageRoute<dynamic>>(), reason: routeName);
      final page = (route! as MaterialPageRoute<dynamic>).builder(
        _FakeContext(),
      );
      expect(page, isA<InvalidRouteScreen>(), reason: routeName);
    }
  });
}

class _FakeContext extends Fake implements BuildContext {}
