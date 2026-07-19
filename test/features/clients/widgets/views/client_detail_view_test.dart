import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/application/appointment_history_providers.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/views/client_detail_view.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockClientsRepo extends Mock implements ClientsRepository {}

const _personClient = ClientRecord(
  id: 'c1',
  name: 'Carol Smith',
  phone: '555-0303',
  address: '2 Main St',
);

const _clientWithContacts = ClientRecord(
  id: 'c2',
  name: 'Acme Corp',
  phone: '555-0101',
  address: '1 Main St',
  contacts: [ClientContact(name: 'Bob Builder', phone: '555-0202')],
);

Widget _wrap(ClientsRepository repo, ClientRecord client) {
  return ProviderScope(
    overrides: [
      clientsRepositoryProvider.overrideWithValue(repo),
      // The detail view now renders the Job History section, which reads the
      // real appointments repo; this test only exercises contacts, so serve it
      // an empty history rather than hitting Firebase.
      clientJobHistoryProvider.overrideWith(
        (ref, clientId) async => <AppointmentRecord>[],
      ),
    ],
    child: ThemeNotifier(
      themeMode: ThemeMode.light,
      toggleTheme: () {},
      textScale: 1,
      setTextScale: (_) {},
      setLanguage: (_) {},
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: lightTheme(),
        home: Scaffold(body: ClientDetailView(client: client)),
      ),
    ),
  );
}

Finder _textFieldFor(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is LabeledTextField && w.label == label,
  ),
  matching: find.byType(TextField),
);

/// Pumps the detail view at a tall viewport (so every edit field is built)
/// and enters edit mode.
Future<void> _pumpInEditMode(
  WidgetTester tester,
  ClientsRepository repo,
  ClientRecord client,
) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(repo, client));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
}

void main() {
  late _MockClientsRepo repo;

  setUpAll(() {
    registerFallbackValue(const ClientRecord(id: ''));
  });

  setUp(() {
    // The edit-save flow consults the contact-link store (SharedPreferences);
    // with no link present the phone-contact sync is a no-op.
    SharedPreferences.setMockInitialValues({});
    repo = _MockClientsRepo();
  });

  testWidgets('the additional contacts section is always available in edit', (
    tester,
  ) async {
    await _pumpInEditMode(tester, repo, _personClient);

    expect(find.text('Additional contacts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing a client prefills its extra contacts', (tester) async {
    await _pumpInEditMode(tester, repo, _clientWithContacts);

    expect(find.widgetWithText(TextField, 'Bob Builder'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving rebuilds contacts from the edited contact cards', (
    tester,
  ) async {
    when(() => repo.updateClient(any())).thenAnswer((_) async {});
    await _pumpInEditMode(tester, repo, _clientWithContacts);

    // The customer's own phone is the first Phone field; the contact card's
    // phone is the second.
    await tester.enterText(_textFieldFor('Phone').first, '555-9999');
    // Let SheetFocusScroll's 280 ms focus-scroll timer fire.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final saved =
        verify(() => repo.updateClient(captureAny())).captured.single
            as ClientRecord;
    // The customer's own phone changed; the extra contact is unchanged.
    expect(saved.phone, '555-9999');
    expect(saved.contacts, const [
      ClientContact(name: 'Bob Builder', phone: '555-0202'),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('view mode shows quick actions only for available details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // _clientWithContacts has a phone and an address but no email.
    await tester.pumpWidget(_wrap(repo, _clientWithContacts));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InkWell, 'Call'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Directions'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Email'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'view mode always offers Save to contacts, even with no details',
    (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // A name-only client has no phone / email / address.
      await tester.pumpWidget(
        _wrap(repo, const ClientRecord(id: 'c3', name: 'Eve')),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InkWell, 'Save'), findsOneWidget);
      expect(find.widgetWithText(InkWell, 'Call'), findsNothing);
      expect(find.widgetWithText(InkWell, 'Directions'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('view mode lists the extra contacts', (tester) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(repo, _clientWithContacts));
    await tester.pumpAndSettle();

    // The extra contact is listed.
    expect(find.text('Bob Builder'), findsOneWidget);
    // The customer's own phone shows once (contact-info card).
    expect(find.text('555-0101'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('view mode shows the saved changes without reopening', (
    tester,
  ) async {
    when(() => repo.updateClient(any())).thenAnswer((_) async {});
    await _pumpInEditMode(tester, repo, _clientWithContacts);

    await tester.enterText(_textFieldFor('Phone').first, '555-9999');
    // Let SheetFocusScroll's 280 ms focus-scroll timer fire.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    // Back in view mode (no edit fields) with the new phone rendered.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('555-9999'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing an extra contact persists the removal', (tester) async {
    when(() => repo.updateClient(any())).thenAnswer((_) async {});
    await _pumpInEditMode(tester, repo, _clientWithContacts);

    // Remove the extra "Bob Builder" contact card.
    await tester.tap(find.byTooltip('Remove contact'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final saved =
        verify(() => repo.updateClient(captureAny())).captured.single
            as ClientRecord;
    expect(saved.contacts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a client drops its phone-contact link', (tester) async {
    SharedPreferences.setMockInitialValues({'contact_link_c1': 'native-7'});
    when(() => repo.deleteClient('c1')).thenAnswer((_) async {});
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(repo, _personClient));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();
    // The confirm dialog's destructive action is also labelled "Delete".
    await tester.tap(find.text('Delete').last);
    // Bounded pumps: the post-delete busy spinner animates forever, so
    // pumpAndSettle would time out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    verify(() => repo.deleteClient('c1')).called(1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('contact_link_c1'), isNull);
    expect(tester.takeException(), isNull);
  });
}
