import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/widgets/fields/client_address_section.dart';
import 'package:scheduling/features/clients/widgets/sheets/add_client_sheet.dart';
import 'package:scheduling/l10n/l10n.dart';

import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';

import '../../../../support/tour_test_support.dart';

class _FakeClientsRepository implements ClientsRepository {
  ClientRecord? added;

  @override
  Future<ClientRecord> addClient(ClientRecord client) async {
    added = client;
    return client.copyWith(id: 'new-id');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    markFormToursSeen();
    _lastResult = null;
  });

  // A viewport tall enough that the whole sheet (a DraggableScrollableSheet at
  // 95% of height) lays out its fields without scrolling, so finders are stable.
  Future<void> setTallViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  // The sheet is presented via showModalBottomSheet (as in the app) so the
  // DraggableScrollableSheet inside FormSheetScaffold gets a real sheet route
  // + Material ancestor, and its post-save Navigator.pop has a route to remove.
  Future<_FakeClientsRepository> pumpSheet(WidgetTester tester) async {
    await setTallViewport(tester);
    final repo = _FakeClientsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [clientsRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: _SheetHost(),
        ),
      ),
    );
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('toggling no-fixed-address hides the address section', (
    tester,
  ) async {
    await pumpSheet(tester);
    expect(find.byType(ClientAddressSection), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(find.byType(ClientAddressSection), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a no-fixed-address client saves with an empty address', (
    tester,
  ) async {
    final repo = await pumpSheet(tester);

    // Customer name (first field) satisfies the name requirement; the phone
    // field satisfies the contact-method requirement. With no-fixed-address on,
    // no address is required.
    await tester.enterText(find.byType(TextField).first, 'City of Montreal');
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone'),
      '5145550000',
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(repo.added, isNotNull);
    expect(repo.added!.noFixedAddress, isTrue);
    expect(repo.added!.address, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a picked type is stored on the record', (tester) async {
    final repo = await pumpSheet(tester);

    await tester.enterText(find.byType(TextField).first, 'Acme');
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone'),
      '5145550000',
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Commercial'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(repo.added!.type, ClientType.commercial);
  });

  testWidgets('tapping the selected type chip clears it back to unset', (
    tester,
  ) async {
    final repo = await pumpSheet(tester);

    await tester.enterText(find.byType(TextField).first, 'Acme');
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone'),
      '5145550000',
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Commercial'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commercial'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(repo.added!.type, ClientType.unset);
  });

  // I4: `repo.added!.name` had zero assertions here, though the stored name IS
  // the Wave customer name — the one field a wrong save renames on live
  // invoices. Both branches of `composeStored`, from the form.
  testWidgets('a PERSON is stored under their phone number', (tester) async {
    final repo = await pumpSheet(tester);

    await tester.enterText(find.byType(TextField).first, 'Marc Tremblay');
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone'),
      '5145550101',
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(repo.added!.name, '(514) 555-0101');
  });

  testWidgets('a COMMERCIAL client keeps its typed name', (tester) async {
    // The type has to reach `composeStored`, or a real company is booked into
    // Wave under a phone number.
    final repo = await pumpSheet(tester);

    await tester.enterText(find.byType(TextField).first, 'Vogas Plumbing');
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone'),
      '5145550101',
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Commercial'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(repo.added!.name, 'Vogas Plumbing');
  });

  testWidgets('access notes are saved', (tester) async {
    final repo = await pumpSheet(tester);

    await tester.enterText(find.byType(TextField).first, 'Acme');
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone'),
      '5145550000',
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.enterText(_fieldLabelled('Access notes'), 'Gate code 1234');

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(repo.added!.accessNotes, 'Gate code 1234');
  });

  testWidgets('an empty name shows the error and does not write', (
    tester,
  ) async {
    final repo = await pumpSheet(tester);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(repo.added, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add and book a job reports the follow-up action', (
    tester,
  ) async {
    final repo = await pumpSheet(tester);

    await tester.enterText(find.byType(TextField).first, 'Acme');
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone'),
      '5145550000',
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add and book a job'));
    await tester.pumpAndSettle();

    expect(repo.added, isNotNull);
    expect(_lastResult?.next, AddClientNext.bookJob);
  });

  testWidgets('the plain Add verb reports no follow-up action', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextField).first, 'Acme');
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone'),
      '5145550000',
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(_lastResult?.next, AddClientNext.none);
  });
}

/// Captured from the sheet's pop so the follow-up action can be asserted.
AddClientResult? _lastResult;

/// LabeledTextField renders its label outside the TextField, so match on the
/// wrapper and descend — the same shape clients_screen_test uses.
Finder _fieldLabelled(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is LabeledTextField && w.label == label,
  ),
  matching: find.byType(TextField),
);

// Hosts the sheet behind a button so opening it creates a poppable modal route
// with the Material ancestor showModalBottomSheet provides.
class _SheetHost extends StatelessWidget {
  const _SheetHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            _lastResult = await showModalBottomSheet<AddClientResult>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const AddClientSheet(),
            );
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}
