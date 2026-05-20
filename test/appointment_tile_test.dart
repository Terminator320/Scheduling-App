// test/appointment_tile_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/appointment_tile.dart';
import 'package:scheduling/shared/widgets/status_chip.dart';

AppointmentRecord _fakeAppt({
  String status = 'confirmed',
  List<String> employeeNames = const ['Sarah Johnson'],
  List<String> employeeIds = const ['e1'],
}) => AppointmentRecord(
  id: '1',
  title: 'Haircut',
  startTime: DateTime(2099, 5, 6, 9),
  endTime: DateTime(2099, 5, 6, 9, 45),
  clientId: 'c1',
  clientName: 'Sarah Johnson',
  clientPhone: '514-555-0101',
  employeeIds: employeeIds,
  employeeNames: employeeNames,
  address: '123 Main St',
  status: status,
  pictures: [],
);

const _colorMap = {'e1': Color(0xFF6366F1)};

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
  setUpAll(() async {
    await initializeDateFormatting('en_CA');
  });

  testWidgets('shows service title', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AppointmentTile(appointment: _fakeAppt(), employeeColorMap: _colorMap),
      ),
    );
    expect(find.textContaining('Haircut'), findsOneWidget);
  });

  testWidgets('shows employee name in subtitle', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AppointmentTile(appointment: _fakeAppt(), employeeColorMap: _colorMap),
      ),
    );
    expect(find.textContaining('Sarah Johnson'), findsOneWidget);
  });

  testWidgets('does NOT show StatusChip for confirmed status', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AppointmentTile(appointment: _fakeAppt(), employeeColorMap: _colorMap),
      ),
    );
    expect(find.byType(StatusChip), findsNothing);
  });

  testWidgets('shows StatusChip for done status', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AppointmentTile(
          appointment: _fakeAppt(status: 'done'),
          employeeColorMap: _colorMap,
        ),
      ),
    );
    expect(find.byType(StatusChip), findsOneWidget);
  });

  testWidgets('shows StatusChip for pending status', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AppointmentTile(
          appointment: _fakeAppt(status: 'pending'),
          employeeColorMap: _colorMap,
        ),
      ),
    );
    expect(find.byType(StatusChip), findsOneWidget);
  });

  testWidgets('shows StatusChip for cancelled status', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AppointmentTile(
          appointment: _fakeAppt(status: 'cancelled'),
          employeeColorMap: _colorMap,
        ),
      ),
    );
    expect(find.byType(StatusChip), findsOneWidget);
  });

  testWidgets('calls onOpen when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        AppointmentTile(
          appointment: _fakeAppt(),
          employeeColorMap: _colorMap,
          onOpen: () async => tapped = true,
        ),
      ),
    );
    await tester.tap(find.byType(AppointmentTile));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('does not overflow at small screen + 2x text scale', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(260 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _wrap(
          AppointmentTile(
            appointment: _fakeAppt(),
            employeeColorMap: _colorMap,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows fallback when employeeNames is empty', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AppointmentTile(
          appointment: _fakeAppt(employeeNames: [], employeeIds: []),
          employeeColorMap: const {},
        ),
      ),
    );
    expect(find.textContaining('Haircut'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
