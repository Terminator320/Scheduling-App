import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/validators/password_requirements.dart';
import 'package:scheduling/features/auth/widgets/password_requirements_checklist.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  Future<void> pumpChecklist(WidgetTester tester, String password) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PasswordRequirementsChecklist(password: password),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  final requirementCount = PasswordRequirement.values.length;

  testWidgets('shows an empty circle for every unmet requirement', (
    tester,
  ) async {
    await pumpChecklist(tester, '');
    expect(
      find.byIcon(Icons.circle_outlined),
      findsNWidgets(requirementCount),
    );
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('shows a checkmark for every met requirement', (tester) async {
    await pumpChecklist(tester, 'Abcdef1!');
    expect(find.byIcon(Icons.check_circle), findsNWidgets(requirementCount));
    expect(find.byIcon(Icons.circle_outlined), findsNothing);
  });

  testWidgets('mixes circles and checkmarks for a partial password', (
    tester,
  ) async {
    // 'abc' meets only the lowercase requirement.
    await pumpChecklist(tester, 'abc');
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(
      find.byIcon(Icons.circle_outlined),
      findsNWidgets(requirementCount - 1),
    );
  });
}
