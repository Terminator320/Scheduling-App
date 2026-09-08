import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/dashboard/screens/dashboard_screen.dart';
import 'package:scheduling/routes/app_routes.dart';

/// The dashboard route's FAIL-CLOSED argument default.
///
/// `isAdmin: args?.isAdmin ?? false` is what stops an argless push from
/// rendering an employee's dashboard with the admin affordances on it — the
/// flag becomes the cards' `showActions`, and a `true` default once showed
/// employees Edit/Cancel/Delete controls the rules then rejected with an opaque
/// `permission-denied`. The whole case was at 0% coverage, so the default and
/// the incident comment beside it were guarding nothing under test.
///
/// It is also the one route deliberately null-TOLERANT: the seven
/// `settings.arguments!` cases below it bang out on purpose, because a route
/// whose entire content is its argument has nothing to render, while this one
/// is the app's home and reached from every back stack.
void main() {
  DashboardScreen screenFor(Object? arguments) {
    final route =
        AppRoutes.onGenerateRoute(
              RouteSettings(name: AppRoutes.dashboard, arguments: arguments),
            )!
            as MaterialPageRoute<dynamic>;
    // The builder is pure — no BuildContext is read before the widget exists.
    return route.builder(_FakeContext()) as DashboardScreen;
  }

  test('an argless push degrades to a NON-admin dashboard', () {
    final screen = screenFor(null);

    expect(screen.isAdmin, isFalse);
    expect(screen.employeeId, '');
    expect(screen.userName, isNull);
    expect(screen.email, isNull);
  });

  test('an argless push does not throw the way the banged routes do', () {
    // The asymmetry is deliberate, and this is the half that documents it: a
    // crash here would cost the user their session, where the degrade costs
    // them a couple of affordances.
    expect(() => screenFor(null), returnsNormally);
  });

  test('real args are passed straight through', () {
    final screen = screenFor(
      const DashboardArgs(
        isAdmin: true,
        employeeId: 'e1',
        userName: 'Sophie',
        email: 'sophie@example.com',
      ),
    );

    expect(screen.isAdmin, isTrue);
    expect(screen.employeeId, 'e1');
    expect(screen.userName, 'Sophie');
    expect(screen.email, 'sophie@example.com');
  });
}

/// The route builder never touches its context, so a stub is enough to call it
/// outside a widget tree.
class _FakeContext extends Fake implements BuildContext {}
