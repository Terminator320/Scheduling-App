import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/dashboard/application/dashboard_providers.dart';

class _MockClientsRepo extends Mock implements ClientsRepository {}

/// Fixed clock: Wednesday 2026-07-08, noon.
final _now = DateTime(2026, 7, 8, 12);

ClientRecord _client(
  String id, {
  DateTime? createdAt,
  bool archived = false,
}) => ClientRecord.fromMap(id, {
  'name': 'Client $id',
  // A legacy doc has no `createdAt` key at all, which is the case under test.
  'createdAt': ?createdAt,
  'archived': archived,
});

void main() {
  late _MockClientsRepo repo;

  setUpAll(() => registerFallbackValue(DateTime(2026)));

  setUp(() => repo = _MockClientsRepo());

  ProviderContainer containerWith(List<ClientRecord> clients) {
    when(
      () => repo.fetchClientsCreatedSince(any()),
    ).thenAnswer((_) async => clients);
    // The listens keep AutoDispose state alive across reads.
    return ProviderContainer(
        overrides: [
          dashboardClockProvider.overrideWithValue(() => _now),
          clientsRepositoryProvider.overrideWithValue(repo),
        ],
      )
      ..listen(dashboardRangeProvider, (_, _) {})
      ..listen(newClientsProvider, (_, _) {})
      ..listen(newClientDatesProvider, (_, _) {});
  }

  test('an archived client is excluded', () async {
    // Owner call 2026-08-10: the dashboard answers "what should I look at
    // now", and an archived client is one you decided not to look at.
    final container = containerWith([
      _client('live', createdAt: DateTime(2026, 7, 7)),
      _client('gone', createdAt: DateTime(2026, 7, 7), archived: true),
    ]);
    addTearDown(container.dispose);

    final clients = await container.read(newClientsProvider.future);

    expect(clients.map((c) => c.id), ['live']);
  });

  test('a client with no createdAt is excluded rather than crashing', () async {
    // The two filters are one guard: `newClientDatesProvider` force-unwraps
    // `createdAt`, so dropping the null test turns a legacy doc into a throw
    // on a screen that has nothing to do with that client.
    final container = containerWith([
      _client('legacy'),
      _client('dated', createdAt: DateTime(2026, 7, 7)),
    ]);
    addTearDown(container.dispose);

    final clients = await container.read(newClientsProvider.future);

    expect(clients.map((c) => c.id), ['dated']);
    expect(container.read(newClientDatesProvider).requireValue, [
      DateTime(2026, 7, 7),
    ]);
  });

  test('an archived client with no createdAt is excluded by both', () async {
    final container = containerWith([_client('both', archived: true)]);
    addTearDown(container.dispose);

    expect(await container.read(newClientsProvider.future), isEmpty);
  });

  test('newest first', () async {
    final container = containerWith([
      _client('older', createdAt: DateTime(2026, 7, 2)),
      _client('newest', createdAt: DateTime(2026, 7, 7)),
      _client('middle', createdAt: DateTime(2026, 7, 4)),
    ]);
    addTearDown(container.dispose);

    final clients = await container.read(newClientsProvider.future);

    expect(clients.map((c) => c.id), ['newest', 'middle', 'older']);
  });

  test('the dates provider agrees with the list it derives from', () async {
    // They exist as one fetch precisely so the KPI count and the list can
    // never disagree about which clients count.
    final container = containerWith([
      _client('a', createdAt: DateTime(2026, 7, 7)),
      _client('archived', createdAt: DateTime(2026, 7, 6), archived: true),
      _client('b', createdAt: DateTime(2026, 7, 5)),
    ]);
    addTearDown(container.dispose);

    final clients = await container.read(newClientsProvider.future);
    final dates = container.read(newClientDatesProvider).requireValue;

    expect(dates, clients.map((c) => c.createdAt).toList());
    expect(dates, hasLength(2));
  });

  test('reads from the whole 8-week window, not the live half', () async {
    // The archived/null filtering is in Dart because this read is bounded and
    // cursor-free; that only holds while it stays the one-shot whole-window
    // read rather than the live listener's range.
    final container = containerWith(const []);
    addTearDown(container.dispose);
    await container.read(newClientsProvider.future);

    final captured = verify(
      () => repo.fetchClientsCreatedSince(captureAny()),
    ).captured;

    expect(captured.single, container.read(dashboardRangeProvider).start);
    expect(
      captured.single,
      isNot(container.read(dashboardLiveRangeProvider).start),
    );
  });
}
