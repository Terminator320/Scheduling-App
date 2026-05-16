import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/l10n/app_localizations.dart';

/// E3: typed `EmployeesFailure` family must surface a localized string —
/// never a raw "Employee email already exists" leaking from the repo.
void main() {
  Future<BuildContext> harness(WidgetTester tester, Locale locale) async {
    late BuildContext captured;
    await tester.pumpWidget(
      Localizations(
        locale: locale,
        delegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        child: Builder(
          builder: (ctx) {
            captured = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return captured;
  }

  testWidgets('emailAlreadyExists resolves to the EN string', (tester) async {
    final context = await harness(tester, const Locale('en'));
    const failure = EmployeesFailureEmailAlreadyExists();
    expect(
      failure.toLocalizedMessage(context),
      AppLocalizations.of(context)!.anEmployeeWithThisEmailAlreadyExists,
    );
  });

  testWidgets('emailAlreadyExists resolves to the FR string', (tester) async {
    final context = await harness(tester, const Locale('fr'));
    const failure = EmployeesFailureEmailAlreadyExists();
    expect(
      failure.toLocalizedMessage(context),
      AppLocalizations.of(context)!.anEmployeeWithThisEmailAlreadyExists,
    );
  });
}
