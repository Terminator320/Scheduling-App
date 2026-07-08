import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/calendar/widgets/sections/appointment_form_fields.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  Future<AppointmentFormControllers> pumpAppointmentForm(
    WidgetTester tester, {
    required double width,
    String clientQuery = '',
    List<ClientRecord> clientResults = const [],
    ValueChanged<ClientRecord>? onSelectClient,
    Future<ClientRecord?> Function(String initialName)? onRequestAddClient,
  }) async {
    tester.view.physicalSize = Size(width, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controllers = AppointmentFormControllers(
      title: TextEditingController(),
      date: TextEditingController(),
      startTime: TextEditingController(),
      endTime: TextEditingController(),
      clientSearch: TextEditingController(),
      address: TextEditingController(),
      notes: TextEditingController(),
      materials: TextEditingController(),
    );
    controllers.clientSearch.text = clientQuery;
    addTearDown(controllers.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AppointmentFormFields(
              controllers: controllers,
              allEmployees: const [],
              selectedClient: null,
              clientResults: clientResults,
              isSearchingClient: false,
              selectedEmployees: const [],
              repeat: RepeatInterval.none,
              useCustomAddress: true,
              errors: const {},
              employeeLabel: 'Employee',
              employeeRequired: false,
              materialsHint: 'Materials',
              photosSection: const SizedBox.shrink(),
              onSearchClients: (_) {},
              onSelectClient: onSelectClient ?? (_) {},
              onClearClient: () {},
              onToggleEmployee: (_) {},
              onPickDate: () {},
              onPickStartTime: () {},
              onPickEndTime: () {},
              onSelectRepeat: (_) {},
              onUseCustomAddress: (_) {},
              onRequestAddClient: onRequestAddClient,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controllers;
  }

  testWidgets('time fields stack vertically on narrow phone widths', (
    tester,
  ) async {
    await pumpAppointmentForm(tester, width: 320);

    final startLabel = tester.getTopLeft(find.text('Start Time'));
    final endLabel = tester.getTopLeft(find.text('End Time'));

    expect(endLabel.dy, greaterThan(startLabel.dy + 20));
    expect((endLabel.dx - startLabel.dx).abs(), lessThan(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline add-client auto-selects the created client', (
    tester,
  ) async {
    const created = ClientRecord(
      id: 'c-new',
      name: 'New Guy',
      address: '9 Rue Test',
    );
    final selected = <ClientRecord>[];
    final controllers = await pumpAppointmentForm(
      tester,
      width: 400,
      clientQuery: 'New', // typed text that matched nothing
      onSelectClient: selected.add,
      onRequestAddClient: (name) async => created,
    );

    await tester.tap(find.byIcon(Icons.person_add_alt_1));
    await tester.pumpAndSettle();

    // The returned client is selected and its name fills the search box.
    expect(selected.single.id, 'c-new');
    expect(controllers.clientSearch.text, 'New Guy');
    expect(tester.takeException(), isNull);
  });
}
