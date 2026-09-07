import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';

void main() {
  Widget app(Map<String, dynamic> userDoc) => ProviderScope(
    overrides: [
      currentUserDocProvider.overrideWith((_) => Stream.value(userDoc)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateRoute: AppRoutes.onGenerateRoute,
      initialRoute: AppRoutes.history,
      onGenerateInitialRoutes: (_) => [
        AppRoutes.onGenerateRoute(
          const RouteSettings(
            name: AppRoutes.history,
            arguments: HistoryArgs(isAdmin: true, employeeId: 'e1'),
          ),
        )!,
      ],
    ),
  );

  testWidgets('a non-admin pushing /history lands on the invalid-link screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const {'role': 'employee', 'status': 'active'}),
    );
    await tester.pump();
    expect(find.byType(InvalidRouteScreen), findsOneWidget);
  });

  testWidgets('an unsettled doc also refuses — the gate fails closed', (
    tester,
  ) async {
    await tester.pumpWidget(app(const {}));
    await tester.pump();
    expect(find.byType(InvalidRouteScreen), findsOneWidget);
  });
}
