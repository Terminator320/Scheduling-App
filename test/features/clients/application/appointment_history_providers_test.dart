import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/clients/application/appointment_history_providers.dart';

class _MockAppointmentsRepo extends Mock implements AppointmentsRepository {}

const HistorySearchKey _leak = (query: 'leak', employeeId: null);

void main() {
  late _MockAppointmentsRepo repo;
  late StreamController<void> localWrites;
  late ProviderContainer container;

  setUp(() {
    repo = _MockAppointmentsRepo();
    localWrites = StreamController<void>.broadcast();
    when(() => repo.onLocalWrite).thenAnswer((_) => localWrites.stream);
    when(() => repo.searchHistory(any())).thenAnswer((_) async => const []);

    container = ProviderContainer(
      overrides: [appointmentsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(() async {
      container.dispose();
      await localWrites.close();
    });
  });

  test('a local appointment write invalidates the committed search results '
      '(a just-deleted visit must not stay listed)', () async {
    container.listen(historySearchProvider(_leak), (_, _) {});
    await container.read(historySearchProvider(_leak).future);
    verify(() => repo.searchHistory('leak')).called(1);

    localWrites.add(null);
    // Let the stream event deliver and the invalidation land.
    await Future<void>.delayed(Duration.zero);
    await container.read(historySearchProvider(_leak).future);

    verify(() => repo.searchHistory('leak')).called(1);
  });

  test('disposing the provider cancels its local-write subscription', () async {
    final sub = container.listen(historySearchProvider(_leak), (_, _) {});
    await container.read(historySearchProvider(_leak).future);
    expect(localWrites.hasListener, isTrue);

    sub.close();
    // AutoDispose teardown runs after the current microtask loop.
    await Future<void>.delayed(Duration.zero);
    expect(localWrites.hasListener, isFalse);
  });
}
