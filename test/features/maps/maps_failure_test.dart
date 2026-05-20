import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/maps/domain/maps_failure.dart';
import 'package:scheduling/l10n/l10n.dart';

/// E3: typed `MapsFailure` family must hold its raw cause for logs but
/// must NOT expose response-body / API noise via `toLocalizedMessage`.
void main() {
  Future<BuildContext> harness(WidgetTester tester) async {
    late BuildContext captured;
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
            captured = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return captured;
  }

  testWidgets('MapsFailureNetwork resolves to addressLookupFailed', (
    tester,
  ) async {
    final context = await harness(tester);
    const failure = MapsFailureNetwork(cause: 'autocomplete HTTP 500');
    expect(
      failure.toLocalizedMessage(context),
      AppLocalizations.of(context).addressLookupFailed,
    );
  });

  testWidgets('MapsFailureParse resolves to couldNotLoadAddressDetails', (
    tester,
  ) async {
    final context = await harness(tester);
    const failure = MapsFailureParse();
    expect(
      failure.toLocalizedMessage(context),
      AppLocalizations.of(context).couldNotLoadAddressDetails,
    );
  });

  testWidgets('MapsFailureRateLimit resolves to tooManyAttempts copy', (
    tester,
  ) async {
    final context = await harness(tester);
    const failure = MapsFailureRateLimit();
    expect(
      failure.toLocalizedMessage(context),
      AppLocalizations.of(context).tooManyAttemptsPleaseTryAgainLater2,
    );
  });

  testWidgets('MapsFailureUnauthorized resolves to retry copy', (
    tester,
  ) async {
    final context = await harness(tester);
    const failure = MapsFailureUnauthorized();
    expect(
      failure.toLocalizedMessage(context),
      AppLocalizations.of(context).somethingWentWrongPleaseTryAgain,
    );
  });

  testWidgets('MapsFailureInvalidInput resolves to generic copy', (
    tester,
  ) async {
    final context = await harness(tester);
    const failure = MapsFailureInvalidInput();
    expect(
      failure.toLocalizedMessage(context),
      AppLocalizations.of(context).somethingWentWrong,
    );
  });

  testWidgets('localized message never leaks the raw cause string', (
    tester,
  ) async {
    final context = await harness(tester);
    // Construct a failure with an obvious sentinel and confirm it doesn't
    // make it into the user-visible string. Locks down the original bug
    // where `throw Exception('Autocomplete failed: ${response.body}')`
    // could surface API payloads to users / logs.
    const sentinel = '!!SENSITIVE_RESPONSE_BODY!!';
    const failures = <MapsFailure>[
      MapsFailureNetwork(cause: sentinel),
      MapsFailureParse(cause: sentinel),
      MapsFailureRateLimit(cause: sentinel),
      MapsFailureUnauthorized(cause: sentinel),
      MapsFailureInvalidInput(cause: sentinel),
    ];
    for (final f in failures) {
      expect(
        f.toLocalizedMessage(context),
        isNot(contains(sentinel)),
        reason: f.runtimeType.toString(),
      );
    }
  });
}
