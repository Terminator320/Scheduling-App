// test/status_chip_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('StatusChip renders Complete label', (tester) async {
    await tester.pumpWidget(
      _wrap(const StatusChip(status: AppointmentStatus.done)),
    );
    expect(find.text('Complete'), findsOneWidget);
  });

  testWidgets('StatusChip renders Pending label', (tester) async {
    await tester.pumpWidget(
      _wrap(const StatusChip(status: AppointmentStatus.pending)),
    );
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('StatusChip renders Cancelled label', (tester) async {
    await tester.pumpWidget(
      _wrap(const StatusChip(status: AppointmentStatus.cancelled)),
    );
    expect(find.text('Cancelled'), findsOneWidget);
  });

  testWidgets('StatusChip renders In Progress label', (tester) async {
    await tester.pumpWidget(
      _wrap(const StatusChip(status: AppointmentStatus.inProgress)),
    );
    expect(find.text('In Progress'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('StatusChip caps user text scaling so the pill stays compact', (
    tester,
  ) async {
    // M6: removed the per-callsite `TextScaler.noScaling` clamp. The chip
    // now caps user scaling at 1.3× internally so callers can't blow up
    // the pill width by setting a large textScaler.

    Widget chipAt(double scale) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: const Scaffold(
          body: Center(child: StatusChip(status: AppointmentStatus.inProgress)),
        ),
      ),
    );

    await tester.pumpWidget(chipAt(1));
    final baseline = tester.getSize(find.text('In Progress')).width;

    await tester.pumpWidget(chipAt(3));
    final scaled = tester.getSize(find.text('In Progress')).width;

    // 1.3× cap + a small epsilon for sub-pixel rounding.
    expect(scaled, lessThanOrEqualTo(baseline * 1.31));
    // Sanity: the chip should still scale a bit at 3.0× (not fully
    // clamped to no-scale). If this fails, the cap is too aggressive.
    expect(scaled, greaterThan(baseline * 1.05));
  });
}
