import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/clients/domain/clients_failure.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  testWidgets('each failure maps to a distinct, non-empty message', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );

    const hasHistory = ClientsFailureHasHistory();
    const notFound = ClientsFailureNotFound();

    expect(hasHistory.toLocalizedMessage(ctx), isNotEmpty);
    expect(notFound.toLocalizedMessage(ctx), isNotEmpty);
    expect(
      hasHistory.toLocalizedMessage(ctx),
      isNot(notFound.toLocalizedMessage(ctx)),
    );
  });
}
