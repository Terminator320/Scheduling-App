import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/analytics/analytics_screens.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/routes/app_routes.dart';

void main() {
  group('analyticsScreenForRoute', () {
    test('maps every pushed route to its canonical screen name', () {
      expect(
        analyticsScreenForRoute(AppRoutes.dashboard),
        AnalyticsScreens.dashboard,
      );
      expect(
        analyticsScreenForRoute(AppRoutes.history),
        AnalyticsScreens.history,
      );
      expect(
        analyticsScreenForRoute(AppRoutes.dayRoute),
        AnalyticsScreens.dayRoute,
      );
      expect(
        analyticsScreenForRoute(AppRoutes.settings),
        AnalyticsScreens.settings,
      );
      expect(
        analyticsScreenForRoute(AppRoutes.myDetails),
        AnalyticsScreens.myDetails,
      );
      expect(analyticsScreenForRoute(AppRoutes.login), AnalyticsScreens.login);
      expect(
        analyticsScreenForRoute(AppRoutes.forgotPassword),
        AnalyticsScreens.forgotPassword,
      );
      expect(
        analyticsScreenForRoute(AppRoutes.accountSetup),
        AnalyticsScreens.accountSetup,
      );
    });

    test('returns null for every route the hub shell owns', () {
      // This is the duplicate guard. `HubTabRedirectRoute` pushes a NAMED route
      // and then hands off to the live shell, which reports the tab itself — so
      // letting the observer see these names would count one arrival path twice
      // and the other two once.
      for (final route in kShellOwnedRoutes) {
        expect(
          analyticsScreenForRoute(route),
          isNull,
          reason: '$route must be reported by HubShellState, not the observer',
        );
      }
    });

    test('the shell-owned set is exactly the four hub tab routes', () {
      expect(kShellOwnedRoutes, {
        AppRoutes.mainCalendar,
        AppRoutes.clients,
        AppRoutes.employees,
        AppRoutes.liveMap,
      });
      expect(kShellOwnedRoutes.length, HubTab.values.length);
    });

    test('returns null for an unnamed or unrecognised route', () {
      // An unnamed modal sheet reports itself from its own widget; a route the
      // map does not know is skipped rather than sent through as a raw path.
      expect(analyticsScreenForRoute(null), isNull);
      expect(analyticsScreenForRoute(''), isNull);
      expect(analyticsScreenForRoute('/not-a-route'), isNull);
    });

    test('a mapped name is always one of the declared screens', () {
      for (final route in [
        AppRoutes.dashboard,
        AppRoutes.history,
        AppRoutes.dayRoute,
        AppRoutes.settings,
        AppRoutes.myDetails,
        AppRoutes.login,
        AppRoutes.forgotPassword,
        AppRoutes.accountSetup,
      ]) {
        expect(
          AnalyticsScreens.allScreens,
          contains(analyticsScreenForRoute(route)),
          reason: route,
        );
      }
    });
  });

  group('analyticsScreenForTab', () {
    test('every hub tab maps to a declared screen name', () {
      for (final tab in HubTab.values) {
        final name = analyticsScreenForTab(tab);
        expect(AnalyticsScreens.allScreens, contains(name), reason: tab.name);
      }
    });

    test('the four tabs map to four distinct names', () {
      final names = HubTab.values.map(analyticsScreenForTab).toSet();
      expect(names.length, HubTab.values.length);
    });
  });

  test('every declared screen name is a valid Firebase-safe token', () {
    // Screen names ride as a `screen_name` parameter value, so the same shape
    // rules apply as to a parameter name.
    for (final name in AnalyticsScreens.allScreens) {
      expect(
        RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name),
        isTrue,
        reason: '"$name" is not snake_case',
      );
    }
  });
}
