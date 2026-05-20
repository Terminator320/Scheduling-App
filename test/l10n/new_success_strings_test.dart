import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/l10n/l10n.dart';

/// N1: new success-notice l10n keys must resolve in both locales (smoke
/// catches a forgotten `gen-l10n` regeneration).
void main() {
  Future<AppLocalizations> _resolve(WidgetTester tester, Locale locale) async {
    late AppLocalizations l;
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
            l = AppLocalizations.of(ctx);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return l;
  }

  testWidgets('appointmentCreated resolves in EN + FR', (tester) async {
    final en = await _resolve(tester, const Locale('en'));
    final fr = await _resolve(tester, const Locale('fr'));
    expect(en.common_appointmentCreated, 'Appointment created');
    expect(fr.common_appointmentCreated, 'Rendez-vous créé');
  });

  testWidgets('all new success keys are non-empty in both locales', (
    tester,
  ) async {
    final en = await _resolve(tester, const Locale('en'));
    final fr = await _resolve(tester, const Locale('fr'));
    for (final s in [
      en.common_clientAdded,
      fr.common_clientAdded,
      en.common_appointmentChangesSaved,
      fr.common_appointmentChangesSaved,
      en.common_appointmentDeleted,
      fr.common_appointmentDeleted,
      en.common_appointmentMarkedAsDone,
      fr.common_appointmentMarkedAsDone,
      en.common_appointmentCancelled,
      fr.common_appointmentCancelled,
    ]) {
      expect(s, isNotEmpty);
    }
  });
}
