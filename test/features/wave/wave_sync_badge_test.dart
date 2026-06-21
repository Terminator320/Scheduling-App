import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/wave/widgets/wave_sync_badge.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _wrap(Widget child) {
  return ThemeNotifier(
    themeMode: ThemeMode.light,
    toggleTheme: () {},
    textScale: 1,
    setTextScale: (_) {},
    setLanguage: (_) {},
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: lightTheme(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('WaveSyncBadge', () {
    testWidgets('renders "Synced with Wave" for syncState synced', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const WaveSyncBadge(syncState: 'synced')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Synced with Wave'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders "Sync pending" for syncState pending', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const WaveSyncBadge(syncState: 'pending')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sync pending'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders "Sync error" for syncState error', (tester) async {
      await tester.pumpWidget(
        _wrap(const WaveSyncBadge(syncState: 'error')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sync error'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders nothing for empty syncState', (tester) async {
      await tester.pumpWidget(
        _wrap(const WaveSyncBadge(syncState: '')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Synced with Wave'), findsNothing);
      expect(find.text('Sync pending'), findsNothing);
      expect(find.text('Sync error'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders nothing for unrecognised syncState', (tester) async {
      await tester.pumpWidget(
        _wrap(const WaveSyncBadge(syncState: 'unknown-state')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Synced with Wave'), findsNothing);
      expect(find.text('Sync pending'), findsNothing);
      expect(find.text('Sync error'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'error badge Semantics includes syncError when provided',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const WaveSyncBadge(
              syncState: 'error',
              syncError: 'timeout connecting to Wave',
            ),
          ),
        );
        await tester.pumpAndSettle();

        final semantics = tester.getSemantics(find.byType(WaveSyncBadge));
        expect(semantics.label, contains('timeout connecting to Wave'));
        expect(tester.takeException(), isNull);
      },
    );
  });
}
