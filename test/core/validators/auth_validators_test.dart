import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/l10n/app_localizations.dart';

/// S3: password validator requires at least 8 characters.
///
/// Uses a tiny [Localizations] harness so `context.l10n.*` resolves to the
/// real generated strings — keeps the test honest about what the user
/// actually sees.

void main() {
  Future<BuildContext> _buildContext(WidgetTester tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        child: Builder(
          builder: (ctx) {
            capturedContext = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return capturedContext;
  }

  testWidgets('AuthValidators.password rejects empty input', (tester) async {
    final context = await _buildContext(tester);
    expect(AuthValidators.password(context, ''), isNotNull);
    expect(AuthValidators.password(context, '   '), isNotNull);
  });

  testWidgets('AuthValidators.password rejects passwords shorter than 8', (
    tester,
  ) async {
    final context = await _buildContext(tester);
    expect(AuthValidators.password(context, '1234567'), isNotNull);
    // The 7-char rejection uses the "must be at least 8" message, not the
    // "please enter" empty-field message.
    expect(
      AuthValidators.password(context, '1234567'),
      AppLocalizations.of(context)!.passwordMustBeAtLeast8Characters,
    );
  });

  testWidgets('AuthValidators.password accepts 8+ char passwords', (
    tester,
  ) async {
    final context = await _buildContext(tester);
    expect(AuthValidators.password(context, '12345678'), isNull);
    expect(
      AuthValidators.password(context, 'a-perfectly-fine-password'),
      isNull,
    );
  });
}
