// Guards against a layout crash — IntrinsicHeight (which stretches the crew
// colour bar) can't query intrinsic dimensions through AutoSizeText's internal
// LayoutBuilder, so the title has to stay a plain Text.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/core/animations/tap_scale.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/calendar/domain/appointment_crew.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_card.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

const _blue = Color(0xFF005CC8);
const _green = Color(0xFF0E9B6E);
const _theo = [AppointmentCrew(name: 'Theo Bell', color: _blue)];

AppointmentRecord _appt({
  String status = 'pending',
  String clientName = 'Marchetti Residence',
  String title = 'Water heater swap',
}) => AppointmentRecord(
  id: 'a1',
  title: title,
  startTime: DateTime(2026, 8, 4, 10, 30),
  endTime: DateTime(2026, 8, 4, 12),
  clientName: clientName,
  employeeIds: const ['e1'],
  employeeNames: const ['Theo Bell'],
  status: status,
);

// endTime in the past with a non-terminal status resolves to `overdue`.
AppointmentRecord _overdueAppt() => AppointmentRecord(
  id: 'a2',
  title: 'Water heater leak',
  startTime: DateTime(2020, 1, 1, 9),
  endTime: DateTime(2020, 1, 1, 10),
  employeeIds: const ['e1'],
);

Widget _wrap(Widget child, {double width = 375}) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: lightTheme(),
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_CA');
  });

  testWidgets('renders title, status chip, mono time range and crew line', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(AppointmentCard(appointment: _appt(), crew: _theo)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Water heater swap'), findsOneWidget);
    expect(find.byType(StatusChip), findsOneWidget);
    // En-dash, per the design — not a hyphen.
    expect(find.textContaining('–'), findsOneWidget);
    expect(find.textContaining('Theo · Marchetti Residence'), findsOneWidget);
  });

  testWidgets('multi-crew collapses to first name plus a count', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AppointmentCard(
          appointment: _appt(),
          crew: const [
            AppointmentCrew(name: 'Theo Bell', color: _blue),
            AppointmentCrew(name: 'Ana Ruiz', color: _green),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Theo +1'), findsOneWidget);
  });

  testWidgets('renders inside a ListView without an intrinsic-layout crash', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          height: 400,
          child: ListView.builder(
            itemCount: 1,
            itemBuilder: (_, _) => Padding(
              padding: const EdgeInsets.all(8),
              child: AppointmentCard(
                appointment: _appt(
                  title:
                      'A fairly long appointment title that needs to wrap onto '
                      'two lines',
                ),
                crew: _theo,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('long appointment title'), findsOneWidget);
  });

  testWidgets('shows a warning glyph only when the visit is overdue', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(AppointmentCard(appointment: _overdueAppt(), crew: _theo)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

    await tester.pumpWidget(
      _wrap(AppointmentCard(appointment: _appt(), crew: _theo)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('cancelled strikes the title through when dimming is on', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AppointmentCard(
          appointment: _appt(status: 'cancelled'),
          crew: _theo,
          dimWhenCancelled: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Water heater swap'));
    expect(title.style?.decoration, TextDecoration.lineThrough);
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(
              of: find.byType(TapScale),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      closeTo(0.6, 0.001),
    );
  });

  testWidgets('cancelled renders plain when dimming is off', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AppointmentCard(
          appointment: _appt(status: 'cancelled'),
          crew: _theo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('Water heater swap'));
    expect(title.style?.decoration, isNot(TextDecoration.lineThrough));
  });

  testWidgets('an unassigned job still renders without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(AppointmentCard(appointment: _appt(), crew: const [])),
    );
    await tester.pumpAndSettle();
    expect(find.text('Water heater swap'), findsOneWidget);
    // No crew, so the meta line falls back to the client alone.
    expect(find.text('Marchetti Residence'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the whole card carries one coherent semantics label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(AppointmentCard(appointment: _appt(), crew: _theo)),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('Water heater swap.*Theo Bell')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('survives 260x640 at a 2.0 text scale', (tester) async {
    tester.view.physicalSize = const Size(260, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: AppointmentCard(
            appointment: _appt(),
            crew: const [
              AppointmentCrew(name: 'Theo Bell', color: _blue),
              AppointmentCrew(name: 'Ana Ruiz', color: _green),
            ],
          ),
        ),
        width: 260,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
