import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/core/utils/debouncer.dart';
import 'package:scheduling/features/maps/application/maps_providers.dart';
import 'package:scheduling/features/maps/domain/models/address_suggestion.dart';
import 'package:scheduling/features/maps/domain/models/parsed_address.dart';
import 'package:scheduling/features/maps/domain/places_repository.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/address_autocomplete_field.dart';

/// 307 lines and no test file at all, on the most-typed-into field in the app.
///
/// Three of the four things left unexercised are guards against BILLED Google
/// Places calls — the `_lastFetched` dedupe, the `_requestId` stale-response
/// discard and the session-token lifecycle (Places bills an autocomplete
/// session as one unit only while its token is reused, so a token that never
/// rotates, or rotates per keystroke, changes the bill). The fourth is the
/// post-dispose path that already shipped a FATAL once.
///
/// NOTE: never `pumpAndSettle` here. The field renders a progress indicator
/// while a lookup is in flight, so settling times out instead of failing.
class _RecordingPlaces implements PlacesRepository {
  List<AddressSuggestion> suggestions = const [];
  ParsedAddress? details;

  /// Session tokens seen, in call order — one per autocomplete AND per detail.
  final tokens = <String>[];
  final queries = <String>[];

  /// When set, the next autocomplete waits on this instead of returning.
  Completer<List<AddressSuggestion>>? gate;
  Object? throws;

  @override
  Future<List<AddressSuggestion>> autocomplete(
    String input, {
    required String sessionToken,
  }) {
    queries.add(input);
    tokens.add(sessionToken);
    final pending = gate;
    if (pending != null) {
      gate = null;
      return pending.future;
    }
    if (throws != null) return Future<List<AddressSuggestion>>.error(throws!);
    return Future.value(suggestions);
  }

  @override
  Future<ParsedAddress> getPlaceDetails(
    String placeId, {
    required String sessionToken,
  }) async {
    tokens.add(sessionToken);
    return details ?? const ParsedAddress();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late TextEditingController controller;
  late _RecordingPlaces places;
  late List<String> reported;

  setUp(() {
    controller = TextEditingController();
    places = _RecordingPlaces();
    reported = [];
  });

  tearDown(() => controller.dispose());

  Widget app({required bool showField}) => ProviderScope(
    overrides: [placesRepositoryProvider.overrideWithValue(places)],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: lightTheme(),
      home: Scaffold(
        body: showField
            ? AddressAutocompleteField(
                controller: controller,
                onChanged: reported.add,
              )
            : const SizedBox.shrink(),
      ),
    ),
  );

  Future<void> pumpField(WidgetTester tester, {bool showField = true}) async {
    await tester.pumpWidget(app(showField: showField));
    await tester.pump();
  }

  /// Types [text] without letting the debounce fire.
  Future<void> typeOnly(WidgetTester tester, String text) =>
      tester.enterText(find.byType(TextField), text);

  /// Lets the debounce fire and any settled future deliver.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(kAddressLookupDebounce + const Duration(milliseconds: 1));
    await tester.pump();
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await typeOnly(tester, text);
    await settle(tester);
  }

  testWidgets('a query below the minimum length never reaches Places', (
    tester,
  ) async {
    // Every request is billed, so the short-query guard is a cost control, not
    // a UX nicety.
    await pumpField(tester);
    await type(tester, '12');

    expect(places.queries, isEmpty);
  });

  testWidgets('a keystroke undone inside the debounce is not re-fetched', (
    tester,
  ) async {
    // `_lastFetched`. Typing a character and deleting it before the debounce
    // fires leaves the field back on text it already has results for — the
    // guard is what stops that costing a second billed call.
    places.suggestions = const [
      AddressSuggestion(placeId: 'p1', description: '1 Main St, Montreal'),
    ];
    await pumpField(tester);
    await type(tester, '1 Main St');
    expect(places.queries, ['1 Main St']);

    await typeOnly(tester, '1 Main Stx');
    await typeOnly(tester, '1 Main St');
    await settle(tester);

    expect(places.queries, ['1 Main St'], reason: 'no second billed call');
  });

  testWidgets('a FAILED query is retried, unlike a settled one', (
    tester,
  ) async {
    // The other half of the dedupe: `_lastFetched` is set on success only, or
    // a transient failure would leave the field permanently unable to look up
    // that address.
    places.throws = Exception('network');
    await pumpField(tester);
    await type(tester, '1 Main St');
    expect(places.queries, ['1 Main St']);

    await typeOnly(tester, '1 Main Stx');
    await typeOnly(tester, '1 Main St');
    await settle(tester);

    expect(places.queries, ['1 Main St', '1 Main St']);
  });

  testWidgets('a stale response is discarded rather than shown', (
    tester,
  ) async {
    // `_requestId`. Two lookups in flight and the SLOWER one landing last
    // would otherwise replace the newer query's suggestions with the older
    // query's — the classic autocomplete race.
    final slow = Completer<List<AddressSuggestion>>();
    places
      ..gate = slow
      ..suggestions = const [
        AddressSuggestion(placeId: 'p2', description: 'FRESH RESULT'),
      ];

    await pumpField(tester);
    await type(tester, 'old query');
    await type(tester, 'new query');
    expect(find.text('FRESH RESULT'), findsOneWidget);

    // The first request answers last, with results for text nobody has now.
    slow.complete(const [
      AddressSuggestion(placeId: 'p1', description: 'STALE RESULT'),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('STALE RESULT'), findsNothing);
    expect(find.text('FRESH RESULT'), findsOneWidget);
  });

  testWidgets('one session token spans the whole autocomplete session', (
    tester,
  ) async {
    // Places bills an autocomplete session as ONE unit only while its token is
    // reused across the keystrokes and the final details call. A token minted
    // per request bills per keystroke instead.
    places
      ..suggestions = const [
        AddressSuggestion(placeId: 'p1', description: '1 Main St, Montreal'),
      ]
      ..details = const ParsedAddress(fullAddress: '1 Main St, Montreal, QC');

    await pumpField(tester);
    await type(tester, '1 Mai');
    await type(tester, '1 Main');
    await tester.tap(find.text('1 Main St, Montreal'));
    await settle(tester);

    expect(places.tokens, hasLength(3));
    expect(places.tokens.toSet(), hasLength(1), reason: 'one billed session');
  });

  testWidgets('a NEW session gets a new token once the last one closed', (
    tester,
  ) async {
    // The token is cleared in `_selectSuggestion`'s finally, so the next
    // address the user looks up starts a fresh billable session rather than
    // riding an expired one.
    places
      ..suggestions = const [
        AddressSuggestion(placeId: 'p1', description: '1 Main St, Montreal'),
      ]
      ..details = const ParsedAddress(fullAddress: '1 Main St, Montreal, QC');

    await pumpField(tester);
    await type(tester, '1 Main');
    await tester.tap(find.text('1 Main St, Montreal'));
    await settle(tester);
    final firstSession = places.tokens.last;

    places.suggestions = const [
      AddressSuggestion(placeId: 'p9', description: '9 Oak Ave, Laval'),
    ];
    // TWO keystrokes, deliberately. `controller.text = ` notifies listeners
    // but does NOT fire a TextField's `onChanged`, so the two
    // `_suppressFetch = true` assignments in `_selectSuggestion` are never
    // consumed by the programmatic writes they guard — the first real
    // keystroke after a selection absorbs one instead. Harmless (the flag is a
    // bool, so exactly one is swallowed) but it is what the field does.
    await type(tester, '9 Oak');
    await type(tester, '9 Oak Ave');

    expect(places.tokens.last, isNot(firstSession));
  });

  testWidgets('a lookup that fails AFTER dispose does not escape as a crash', (
    tester,
  ) async {
    // The known-FATAL path. `_fetch` runs from a Debouncer timer with no
    // caller left to catch it, so a `ref.read` below the await threw a
    // StateError straight into the zone handler — every time an address lookup
    // failed after its sheet was dismissed.
    final gate = Completer<List<AddressSuggestion>>();
    places.gate = gate;

    await pumpField(tester);
    await type(tester, '1 Main St');

    // The sheet closes while Places is still thinking.
    await pumpField(tester, showField: false);
    gate.completeError(Exception('network'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the clear button drops the suggestions and tells the host', (
    tester,
  ) async {
    // A programmatic `controller.clear()` never fires the field's own
    // onChanged, so without the explicit call the host keeps an address the
    // user can no longer see.
    places.suggestions = const [
      AddressSuggestion(placeId: 'p1', description: '1 Main St, Montreal'),
    ];

    await pumpField(tester);
    await type(tester, '1 Main St');
    expect(find.text('1 Main St, Montreal'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await settle(tester);

    expect(reported.last, '');
    expect(find.text('1 Main St, Montreal'), findsNothing);
  });
}
