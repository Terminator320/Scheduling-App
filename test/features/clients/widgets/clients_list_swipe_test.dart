import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/cards/client_tile.dart';
import 'package:scheduling/features/clients/widgets/views/clients_list_view.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockClientsRepo extends Mock implements ClientsRepository {}

ClientRecord _clientWithJobs(int jobs) =>
    ClientRecord(id: 'c1', name: 'Acme', jobCount: jobs);

Widget _wrap(ClientsRepository repo, {Widget? body}) => ProviderScope(
  overrides: [
    clientsRepositoryProvider.overrideWithValue(repo),
    // The archive path runs through `guardedOffline` first, and the real
    // provider is a plugin stream that never settles under the harness.
    isOfflineProvider.overrideWithValue(false),
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
      home: Scaffold(
        body: body ?? const ClientsListView(searchQuery: '', isAdmin: true),
      ),
    ),
  ),
);

_MockClientsRepo _repoWith(ClientRecord client) {
  final repo = _MockClientsRepo();
  when(
    () => repo.fetchClientsPage(
      after: any(named: 'after'),
      limit: any(named: 'limit'),
    ),
  ).thenAnswer((_) async => [client]);
  when(
    () => repo.setClientArchived(any(), archived: any(named: 'archived')),
  ).thenAnswer((_) async {});
  when(() => repo.deleteClient(any())).thenAnswer((_) async {});
  return repo;
}

/// Drags far enough to reveal the action pane, but not far enough to commit
/// the dismissible.
Future<_MockClientsRepo> _pumpAndSwipe(
  WidgetTester tester,
  ClientRecord client,
) async {
  final repo = _repoWith(client);

  await tester.pumpWidget(_wrap(repo));
  await tester.pumpAndSettle();
  await tester.drag(find.byType(ClientTile).first, const Offset(-300, 0));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('swipe offers Archive but not Delete for a client with history', (
    tester,
  ) async {
    await _pumpAndSwipe(tester, _clientWithJobs(12));

    // canDeleteClient is advisory UI: the server would refuse this delete, so
    // the swipe must not offer it in the first place.
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swipe offers Delete only when there are no jobs', (
    tester,
  ) async {
    await _pumpAndSwipe(tester, _clientWithJobs(0));

    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown job count withholds Delete', (tester) async {
    // jobCount is lazily backfilled, so null means "not counted yet".
    await _pumpAndSwipe(tester, const ClientRecord(id: 'c1', name: 'Acme'));

    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('what a FULL swipe commits', () {
    /// Drags past the `DismissiblePane` threshold so `onDismissed` fires.
    ///
    /// Incrementally, not as one `tester.drag`: the pane registers its
    /// dismiss listener only once it has been built, so a single-frame drag
    /// arrives before `isDismissibleReady` and merely opens the pane.
    Future<_MockClientsRepo> fullSwipe(
      WidgetTester tester,
      ClientRecord client,
    ) async {
      final repo = _repoWith(client);
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ClientTile).first),
      );
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(-78, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('a full swipe archives, and never deletes', (tester) async {
      // The label assertions above all pass with
      // `DismissiblePane(onDismissed: () => deleteClient(client))` in place —
      // and that gesture would then IRREVERSIBLY delete a client with one
      // uncomfirmed swipe. CLAUDE.md: "A full swipe commits Archive ONLY.
      // Delete is never gesture-committed."
      final repo = await fullSwipe(tester, _clientWithJobs(0));

      verify(() => repo.setClientArchived('c1', archived: true)).called(1);
      verifyNever(() => repo.deleteClient(any()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a full swipe on an archived client un-archives it', (
      tester,
    ) async {
      // The pane is one toggle, so the gesture follows the stored flag rather
      // than always writing `true`.
      final repo = await fullSwipe(
        tester,
        const ClientRecord(id: 'c1', name: 'Acme', archived: true),
      );

      verify(() => repo.setClientArchived('c1', archived: false)).called(1);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('ClientTile itself carries no Slidable', (tester) async {
    // The Slidable is wrapped around the tile by ClientsListView, never built
    // into the tile — the booking flow reuses ClientTile to pick a client and
    // must not inherit archive/delete along with it.
    await tester.pumpWidget(
      _wrap(
        _MockClientsRepo(),
        body: ClientTile(client: _clientWithJobs(0), onOpen: () async {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ClientTile), findsOneWidget);
    expect(find.byType(Slidable), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
