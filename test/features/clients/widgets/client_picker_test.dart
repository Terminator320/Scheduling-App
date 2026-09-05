import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/models/recent_client.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_search_status.dart';
import 'package:scheduling/features/clients/domain/policies/phone_query_policy.dart';
import 'package:scheduling/features/clients/widgets/fields/client_picker.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  const marie = ClientRecord(
    id: 'c1',
    name: 'Marie Tremblay',
    phone: '5145628332',
  );
  const jp = ClientRecord(id: 'c2', name: 'J-P Gagnon', phone: '5145628901');
  const recents = <RecentClient>[
    (clientId: 'c1', name: 'Marie Tremblay', phone: '5145628332', address: ''),
  ];

  Widget harness({
    required TextEditingController controller,
    List<ClientRecord> results = const [],
    ClientSearchStatus status = const ClientSearchStatus(),
    List<RecentClient> recentClients = recents,
    bool isSearching = false,
    ValueChanged<ClientRecord>? onSelect,
    VoidCallback? onRetry,
    VoidCallback? onAddNew,
    double textScale = 1,
  }) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: ClientPicker(
          controller: controller,
          results: results,
          status: status,
          recentClients: recentClients,
          isSearching: isSearching,
          onChanged: (_) {},
          onModeChanged: (_) {},
          onSelect: onSelect ?? (_) {},
          onRetry: onRetry ?? () {},
          onAddNew: onAddNew,
        ),
      ),
    ),
  );

  testWidgets('at rest both mode segments are shown and neither is selected',
      (tester) async {
    await tester.pumpWidget(harness(controller: TextEditingController()));
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('Name or address'), findsOneWidget);
    expect(find.text('Tap Phone to start'), findsOneWidget);
  });

  testWidgets('holding shows the digit tally and no rows', (tester) async {
    await tester.pumpWidget(harness(
      controller: TextEditingController(text: '(514) 5'),
      status: const ClientSearchStatus(digitsTyped: 4),
    ));
    expect(find.text('4 of 10'), findsOneWidget);
    expect(find.text('Keep going'), findsOneWidget);
    expect(find.text('Attach'), findsNothing);
  });

  testWidgets('recents are filtered by the typed digits while holding',
      (tester) async {
    await tester.pumpWidget(harness(
      controller: TextEditingController(text: '514'),
      status: const ClientSearchStatus(digitsTyped: 3),
    ));
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Marie Tremblay'), findsOneWidget);
  });

  testWidgets('an exact match is labelled and carries an Attach button',
      (tester) async {
    await tester.pumpWidget(harness(
      controller: TextEditingController(text: '(514) 562-8332'),
      results: [marie],
      status: const ClientSearchStatus(
        digitsTyped: 10,
        answeredQuery: '5145628332',
        answeredRung: PhoneRung.canonical,
      ),
    ));
    expect(find.text('Exact match'), findsOneWidget);
    expect(find.text('Attach'), findsOneWidget);
  });

  testWidgets('tapping the row attaches, and nothing attaches on its own',
      (tester) async {
    ClientRecord? attached;
    await tester.pumpWidget(harness(
      controller: TextEditingController(text: '(514) 562-8332'),
      results: [marie],
      status: const ClientSearchStatus(
        digitsTyped: 10,
        answeredRung: PhoneRung.canonical,
      ),
      onSelect: (c) => attached = c,
    ));
    expect(attached, isNull, reason: 'never auto-attach');
    await tester.tap(find.text('Attach'));
    await tester.pump();
    expect(attached, marie);
  });

  testWidgets('a fallback answer is labelled as closest, not as matches',
      (tester) async {
    await tester.pumpWidget(harness(
      controller: TextEditingController(text: '(514) 562-8233'),
      results: [marie, jp],
      status: const ClientSearchStatus(
        digitsTyped: 10,
        answeredQuery: '5145628',
        answeredRung: PhoneRung.firstSeven,
      ),
      onAddNew: () {},
    ));
    expect(find.text('Closest numbers on file'), findsOneWidget);
    expect(find.text('None of these — new client'), findsOneWidget);
  });

  testWidgets('a failed search is not an empty one', (tester) async {
    var retried = false;
    await tester.pumpWidget(harness(
      controller: TextEditingController(text: '(514) 562-8332'),
      status: const ClientSearchStatus(digitsTyped: 10, failed: true),
      onRetry: () => retried = true,
    ));
    expect(find.text("Couldn't check that number"), findsOneWidget);
    expect(find.text('No clients found'), findsNothing);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('add-new is absent when the host offers no callback',
      (tester) async {
    await tester.pumpWidget(harness(
      controller: TextEditingController(text: '(514) 562-8233'),
      status: const ClientSearchStatus(digitsTyped: 10),
    ));
    expect(find.textContaining('new client'), findsNothing);
  });

  testWidgets('no overflow on a small phone at 2x text', (tester) async {
    tester.view.physicalSize = const Size(260, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(harness(
      controller: TextEditingController(text: '(514) 562-8332'),
      results: [marie, jp],
      status: const ClientSearchStatus(
        digitsTyped: 10,
        answeredRung: PhoneRung.canonical,
      ),
      textScale: 2,
    ));
    expect(tester.takeException(), isNull);
  });
}
