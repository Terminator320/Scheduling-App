import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';
import 'package:scheduling/shared/widgets/feedback/status_pill.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: lightTheme(),
  home: Scaffold(body: child),
);

void main() {
  test(
    'scheduled and cancelled share the neutral fill with different text',
    () {
      final theme = lightTheme();
      final status = theme.statusColors;
      expect(status.neutralContainer, AppColors.paper);
      expect(status.onNeutralContainer, AppColors.ink60);
      expect(status.onNeutralContainerMuted, AppColors.ink25);
    },
  );

  testWidgets('a pending chip renders neutral, not amber', (tester) async {
    await tester.pumpWidget(
      _wrap(const StatusChip(status: AppointmentStatus.pending)),
    );
    final pill = tester.widget<StatusPill>(find.byType(StatusPill));
    expect(pill.background, lightTheme().statusColors.neutralContainer);
    expect(pill.foreground, lightTheme().statusColors.onNeutralContainer);
  });

  testWidgets('a cancelled chip leaves the error palette', (tester) async {
    await tester.pumpWidget(
      _wrap(const StatusChip(status: AppointmentStatus.cancelled)),
    );
    final pill = tester.widget<StatusPill>(find.byType(StatusPill));
    expect(pill.background, lightTheme().statusColors.neutralContainer);
    expect(pill.foreground, lightTheme().statusColors.onNeutralContainerMuted);
    expect(pill.background, isNot(lightTheme().colorScheme.errorContainer));
  });
}
