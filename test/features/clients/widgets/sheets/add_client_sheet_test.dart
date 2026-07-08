import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/fields/client_address_section.dart';
import 'package:scheduling/features/clients/widgets/sheets/add_client_sheet.dart';
import 'package:scheduling/l10n/l10n.dart';

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
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

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

    await tester.tap(find.text('Save Client'));
    await tester.pumpAndSettle();

    expect(repo.added, isNotNull);
    expect(repo.added!.noFixedAddress, isTrue);
    expect(repo.added!.address, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

// Hosts the sheet behind a button so opening it creates a poppable modal route
// with the Material ancestor showModalBottomSheet provides.
class _SheetHost extends StatelessWidget {
  const _SheetHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const AddClientSheet(),
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}
