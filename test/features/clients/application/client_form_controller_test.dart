import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/clients/application/client_form_controller.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/data/contact_link_store.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';

class _MockClientsRepo extends Mock implements ClientsRepository {}

class _MockContactLinkStore extends Mock implements ContactLinkStore {}

const _client = ClientRecord(
  id: 'c1',
  name: 'Jane Doe',
  phone: '555-0001',
  address: '123 Main St',
);

void main() {
  setUpAll(() {
    registerFallbackValue(_client);
  });

  late _MockClientsRepo repo;
  late _MockContactLinkStore linkStore;
  late ProviderContainer container;

  setUp(() {
    repo = _MockClientsRepo();
    linkStore = _MockContactLinkStore();

    // No linked phone contact by default: the best-effort sync exits before
    // touching any platform channel.
    when(() => linkStore.contactIdFor(any())).thenAnswer((_) async => null);
    when(() => linkStore.unlink(any())).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [
        clientsRepositoryProvider.overrideWithValue(repo),
        contactLinkStoreProvider.overrideWithValue(linkStore),
      ],
    );
    addTearDown(container.dispose);
  });

  ClientFormController notifier() =>
      container.read(clientFormControllerProvider.notifier);

  ClientFormActivity activity() => container.read(clientFormControllerProvider);

  int refreshCount() => container.read(clientsRefreshProvider);

  group('addClient', () {
    test('persists, bumps the list refresh and reports saved', () async {
      when(() => repo.addClient(any())).thenAnswer((_) async {});

      final outcome = await notifier().addClient(_client);

      expect(outcome, isA<ClientSaved>());
      expect((outcome as ClientSaved).client, _client);
      verify(() => repo.addClient(_client)).called(1);
      expect(refreshCount(), 1);
      // Stays saving on success: the sheet keeps its spinner while it pops.
      expect(activity().isSaving, isTrue);
    });

    test('reports the failure without bumping the refresh', () async {
      when(() => repo.addClient(any())).thenThrow(Exception('offline'));

      final outcome = await notifier().addClient(_client);

      expect(outcome, isA<ClientSaveFailed>());
      expect(refreshCount(), 0);
      expect(activity().isSaving, isFalse);
    });
  });

  group('updateClient', () {
    test('persists, bumps the refresh, syncs the linked contact and '
        'reports saved', () async {
      when(() => repo.updateClient(any())).thenAnswer((_) async {});

      final outcome = await notifier().updateClient(_client);

      expect(outcome, isA<ClientSaved>());
      verify(() => repo.updateClient(_client)).called(1);
      verify(() => linkStore.contactIdFor('c1')).called(1);
      expect(refreshCount(), 1);
      expect(activity().isSaving, isFalse);
    });

    test('a failing contact-link lookup never fails the save', () async {
      when(() => repo.updateClient(any())).thenAnswer((_) async {});
      when(
        () => linkStore.contactIdFor(any()),
      ).thenAnswer((_) async => throw Exception('prefs flake'));

      final outcome = await notifier().updateClient(_client);

      expect(outcome, isA<ClientSaved>());
      expect(refreshCount(), 1);
    });

    test('reports the failure without bumping the refresh', () async {
      when(() => repo.updateClient(any())).thenThrow(Exception('offline'));

      final outcome = await notifier().updateClient(_client);

      expect(outcome, isA<ClientSaveFailed>());
      expect(refreshCount(), 0);
      verifyNever(() => linkStore.contactIdFor(any()));
      expect(activity().isSaving, isFalse);
    });
  });

  group('deleteClient', () {
    test('deletes, unlinks the phone contact and bumps the refresh', () async {
      when(() => repo.deleteClient(any())).thenAnswer((_) async {});

      final outcome = await notifier().deleteClient('c1');

      expect(outcome, isA<ClientDeleted>());
      verify(() => repo.deleteClient('c1')).called(1);
      verify(() => linkStore.unlink('c1')).called(1);
      expect(refreshCount(), 1);
      expect(activity().isDeleting, isFalse);
    });

    test('a failing unlink never fails the delete', () async {
      when(() => repo.deleteClient(any())).thenAnswer((_) async {});
      when(
        () => linkStore.unlink(any()),
      ).thenAnswer((_) async => throw Exception('prefs flake'));

      final outcome = await notifier().deleteClient('c1');

      expect(outcome, isA<ClientDeleted>());
      expect(refreshCount(), 1);
    });

    test('reports the failure without bumping the refresh', () async {
      when(() => repo.deleteClient(any())).thenThrow(Exception('offline'));

      final outcome = await notifier().deleteClient('c1');

      expect(outcome, isA<ClientDeleteFailed>());
      expect(refreshCount(), 0);
      verifyNever(() => linkStore.unlink(any()));
      expect(activity().isDeleting, isFalse);
    });
  });
}
