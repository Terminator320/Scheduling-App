// Guards against the IntrinsicHeight + LayoutBuilder layout crash: the card's
// IntrinsicHeight (which stretches the employee-color bar) queries intrinsic
// dimensions, which AutoSizeText's internal LayoutBuilder cannot answer. The
// title must stay a plain Text. See appointment_card.dart:49.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_card.dart';
import 'package:scheduling/l10n/l10n.dart';

AppointmentRecord _fakeAppt() => AppointmentRecord(
  id: '1',
  title: 'A fairly long appointment title that needs to wrap onto two lines',
  startTime: DateTime(2099, 5, 6, 9),
  endTime: DateTime(2099, 5, 6, 9, 45),
  employeeIds: const ['e1'],
);

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Column(children: [Expanded(child: child)]),
  ),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_CA');
  });

  testWidgets('renders inside a ListView without an intrinsic-layout crash', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ListView.builder(
          itemCount: 1,
          itemBuilder: (_, _) => Padding(
            padding: const EdgeInsets.all(8),
            child: AppointmentCard(
              appointment: _fakeAppt(),
              employeeColor: const Color(0xFF6366F1),
              employeeName: 'Sarah Johnson',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('long appointment title'), findsOneWidget);
  });
}
