import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/job_template.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/calendar/widgets/sections/appointment_form_fields.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/sheet_panel.dart';
import 'package:scheduling/shared/widgets/fields/sheet_field_row.dart';

void main() {
  Future<AppointmentFormControllers> pumpAppointmentForm(
    WidgetTester tester, {
    required double width,
    String clientQuery = '',
    List<ClientRecord> clientResults = const [],
    ValueChanged<ClientRecord>? onSelectClient,
    Future<ClientRecord?> Function(String initialName)? onRequestAddClient,
    ValueChanged<JobTemplate>? onApplyTemplate,
    Map<String, AppointmentFormError> errors = const {},
    bool isPersonal = false,
    ValueChanged<bool>? onPersonalChanged,
    bool showPersonalSwitch = true,
    bool isAllDay = false,
    ValueChanged<bool>? onAllDayChanged,
    bool isMultiDay = false,
    bool isOvernight = false,
    int spanLength = 1,
  }) async {
    tester.view.physicalSize = Size(width, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controllers = AppointmentFormControllers(
      title: TextEditingController(),
      date: TextEditingController(),
      endDate: TextEditingController(),
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
              isPersonal: isPersonal,
              onPersonalChanged: showPersonalSwitch
                  ? (onPersonalChanged ?? (_) {})
                  : null,
              isAllDay: isAllDay,
              onAllDayChanged: onAllDayChanged ?? (_) {},
              isMultiDay: isMultiDay,
              isOvernight: isOvernight,
              spanLength: spanLength,
              errors: errors,
              employeeLabel: 'Employee',
              employeeRequired: false,
              materialsHint: 'Materials',
              photosSection: const SizedBox.shrink(),
              onSearchClients: (_) {},
              onSelectClient: onSelectClient ?? (_) {},
              onClearClient: () {},
              onToggleEmployee: (_) {},
              onPickDate: () {},
              onPickEndDate: () {},
              onPickStartTime: () {},
              onPickEndTime: () {},
              onSelectRepeat: (_) {},
              onUseCustomAddress: (_) {},
              onRequestAddClient: onRequestAddClient,
              onApplyTemplate: onApplyTemplate,
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

  testWidgets('job template chips fire onApplyTemplate with the picked type', (
    tester,
  ) async {
    JobTemplate? picked;
    await pumpAppointmentForm(
      tester,
      width: 400,
      onApplyTemplate: (t) => picked = t,
    );

    expect(find.text('TEMPLATES'), findsOneWidget);
    await tester.tap(find.text('Water heater'));
    await tester.pumpAndSettle();
    expect(picked, JobTemplate.waterHeater);
  });

  testWidgets('no template chips render without onApplyTemplate (edit flow)', (
    tester,
  ) async {
    await pumpAppointmentForm(tester, width: 400);
    expect(find.text('TEMPLATES'), findsNothing);
    expect(find.text('Water heater'), findsNothing);
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

  testWidgets('renders the mono section labels', (tester) async {
    await pumpAppointmentForm(tester, width: 400, onApplyTemplate: (_) {});

    expect(find.text('TEMPLATES'), findsOneWidget);
    expect(find.text('WHO'), findsOneWidget);
    expect(find.text('SCHEDULE'), findsOneWidget);
    expect(find.text('DETAILS'), findsOneWidget);
  });

  testWidgets('the date and time pickers render as panel rows', (tester) async {
    await pumpAppointmentForm(tester, width: 400);

    // Start/end date, start/end time and repeat — pickers, not text entry, and
    // all in the one schedule panel.
    expect(find.byType(SheetFieldRow), findsNWidgets(5));
    expect(find.byType(SheetPanel), findsOneWidget);
  });

  testWidgets('the schedule panel offers a start and an end date', (
    tester,
  ) async {
    await pumpAppointmentForm(tester, width: 400);

    expect(find.text('Start date'), findsOneWidget);
    expect(find.text('End date'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the all-day switch renders on a client job too', (tester) async {
    await pumpAppointmentForm(tester, width: 400);

    expect(find.text('All day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a multi-day job labels its times as a daily window', (
    tester,
  ) async {
    await pumpAppointmentForm(
      tester,
      width: 400,
      isMultiDay: true,
      spanLength: 3,
    );

    expect(find.text('Start time · each day'), findsOneWidget);
    expect(find.text('End time · each day'), findsOneWidget);
    expect(find.text('3 days'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an overnight multi-day job counts nights', (tester) async {
    await pumpAppointmentForm(
      tester,
      width: 400,
      isMultiDay: true,
      isOvernight: true,
      spanLength: 2,
    );

    expect(find.text('Start time · each night'), findsOneWidget);
    expect(find.text('End time · next morning'), findsOneWidget);
    expect(find.text('2 nights'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single-day job shows no run length beside the end date', (
    tester,
  ) async {
    await pumpAppointmentForm(tester, width: 400, spanLength: 3);

    expect(find.text('3 days'), findsNothing);
    expect(find.text('3 nights'), findsNothing);
    expect(find.text('Start Time'), findsOneWidget);
    expect(find.text('End Time'), findsOneWidget);
  });

  testWidgets('a personal job hides the client picker and the address', (
    tester,
  ) async {
    await pumpAppointmentForm(tester, width: 400, isPersonal: true);

    expect(find.text('Personal job'), findsOneWidget);
    expect(find.text('Client'), findsNothing);
    expect(find.text('Address'), findsNothing);
    // The rest of the form is untouched.
    expect(find.text('WHO'), findsOneWidget);
    expect(find.text('DETAILS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching a job to personal clears the hidden fields', (
    tester,
  ) async {
    final toggled = <bool>[];
    final controllers = await pumpAppointmentForm(
      tester,
      width: 400,
      clientQuery: 'Acme Ltd',
      onPersonalChanged: toggled.add,
    );
    controllers.address.text = '9 Rue Test';

    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    expect(toggled, [true]);
    // Neither field is visible any more, so neither may keep its value.
    expect(controllers.clientSearch.text, isEmpty);
    expect(controllers.address.text, isEmpty);
  });

  testWidgets('an all-day personal job drops the start and end rows', (
    tester,
  ) async {
    await pumpAppointmentForm(
      tester,
      width: 400,
      isPersonal: true,
      isAllDay: true,
    );

    expect(find.text('All day'), findsOneWidget);
    // Only the date pair is left in the schedule panel.
    expect(find.byType(SheetFieldRow), findsNWidgets(2));
    expect(find.text('Start Time'), findsNothing);
    expect(find.text('End Time'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a personal job drops the templates, repeat and job-site fields',
    (
      tester,
    ) async {
      await pumpAppointmentForm(
        tester,
        width: 400,
        isPersonal: true,
        onApplyTemplate: (_) {},
      );

      expect(find.text('TEMPLATES'), findsNothing);
      expect(find.text('Water heater'), findsNothing);
      expect(find.text('Repeat'), findsNothing);
      expect(find.text('Materials needed'), findsNothing);
      expect(find.text('Pictures'), findsNothing);
    },
  );

  testWidgets('the personal switch is hidden without a change callback', (
    tester,
  ) async {
    // The edit flow passes null on a job that was never personal.
    await pumpAppointmentForm(
      tester,
      width: 400,
      showPersonalSwitch: false,
    );
    expect(find.text('Personal job'), findsNothing);
    expect(find.text('Client'), findsOneWidget);
  });

  testWidgets('a picker row surfaces its validation error', (tester) async {
    await pumpAppointmentForm(
      tester,
      width: 400,
      errors: const {'date': AppointmentFormError.dateRequired},
    );

    // The row surfaces the validator's message inline, not a bare red border.
    expect(find.text('Please select a date'), findsOneWidget);
  });
}
