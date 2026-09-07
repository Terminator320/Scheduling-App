import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/application/field_notes_provider.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/field_note.dart';
import 'package:scheduling/features/calendar/widgets/views/details_field_notes_view.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  AppointmentRecord appointment({String fieldNotes = ''}) => AppointmentRecord(
    id: 'a1',
    title: 'Leak',
    startTime: DateTime(2026, 9, 6, 9),
    endTime: DateTime(2026, 9, 6, 10),
    fieldNotes: fieldNotes,
  );

  Widget harness(
    AppointmentRecord record,
    List<FieldNote> notes, {
    bool truncated = false,
    Map<String, String> roster = const {},
  }) => ProviderScope(
        overrides: [
          appointmentFieldNotesProvider.overrideWith(
            (ref, id) async => (notes: notes, truncated: truncated),
          ),
          employeeNameMapProvider.overrideWithValue(roster),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: DetailsFieldNotesView(appointment: record)),
        ),
      );

  testWidgets('an admin sees each note and who wrote it', (tester) async {
    await tester.pumpWidget(
      harness(appointment(), [
        FieldNote(
          id: 'n1',
          text: 'Copper feed corroded at the elbow.',
          authorId: 'e1',
          authorName: 'Marc Tremblay',
          createdAt: DateTime(2026, 9, 6, 8, 42),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copper feed corroded at the elbow.'), findsOneWidget);
    expect(find.textContaining('Marc Tremblay'), findsOneWidget);
  });

  testWidgets('the legacy string renders unattributed at the top', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(appointment(fieldNotes: 'Valve is behind the dryer.'), const []),
    );
    await tester.pumpAndSettle();
    expect(find.text('Valve is behind the dryer.'), findsOneWidget);
  });

  testWidgets('an empty record renders NOTHING', (tester) async {
    await tester.pumpWidget(harness(appointment(), const []));
    await tester.pumpAndSettle();
    // The empty-omitted rule the rest of the sheet follows.
    expect(find.text('CREW NOTES'), findsNothing);
  });

  testWidgets('the displayed author comes from authorId, not the stored name', (
    tester,
  ) async {
    // S1: `authorName` is not pinned by the rules, so a note filed under a
    // colleague's name must still render as its real author.
    await tester.pumpWidget(
      harness(
        appointment(),
        [
          FieldNote(
            id: 'n1',
            text: 'Swapped the cartridge.',
            authorId: 'e2',
            authorName: 'Marc Tremblay',
            createdAt: DateTime(2026, 9, 6, 8, 42),
          ),
        ],
        roster: const {'e1': 'Marc Tremblay', 'e2': 'Alex Roy'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Alex Roy'), findsOneWidget);
    expect(find.textContaining('Marc Tremblay'), findsNothing);
  });

  testWidgets('an unresolvable authorId falls back to the stored name', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(appointment(), [
        FieldNote(
          id: 'n1',
          text: 'Swapped the cartridge.',
          authorId: 'gone',
          authorName: 'Former Staff',
          createdAt: DateTime(2026, 9, 6, 8, 42),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Former Staff'), findsOneWidget);
  });

  testWidgets('a truncated thread says so', (tester) async {
    await tester.pumpWidget(
      harness(
        appointment(),
        [FieldNote(id: 'n1', text: 'Note.', createdAt: DateTime(2026, 9, 6))],
        truncated: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('most recent'), findsOneWidget);
  });
}
