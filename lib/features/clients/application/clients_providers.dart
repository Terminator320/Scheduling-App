import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/clients/data/firebase_clients_repository.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

final clientsRepositoryProvider = Provider<ClientsRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return FirebaseClientsRepository(firestore);
});

/// Bumped after any client write so paginated list refreshes.
final clientsRefreshProvider = NotifierProvider<ClientsRefresh, int>(
  ClientsRefresh.new,
);

class ClientsRefresh extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Live view of one client doc, keyed by doc id. AutoDispose so the listener is
/// dropped the moment the detail surface closes.
///
/// The Wave sync badge is the reason this is a listener and not a read: every
/// other client surface here is a one-shot read (a paginated page, or the
/// cached scan window), and `wave.syncState` is function-owned — it goes
/// `pending` after the save returns and `synced` up to five minutes later, so
/// a record handed to a screen can never show it. It also deliberately does
/// NOT patch the repository's search/scan cache: that cache is patched on
/// WRITE (`_patchWindow`), and `ClientRecord.toMap()` omits `wave` there, so
/// the cached copy keeps a stale sync state by design.
final clientStreamProvider = StreamProvider.autoDispose
    .family<ClientRecord?, String>(
      (ref, id) => ref.watch(clientsRepositoryProvider).watchClient(id),
    );

/// Full client search with relevance scoring. AutoDispose frees the results once each
/// query instance is no longer watched.
final clientSearchProvider = FutureProvider.autoDispose
    .family<List<ClientRecord>, String>((
      ref,
      query,
    ) async {
      if (!ClientSearchPolicy.shouldSearch(query)) return const [];
      // Watching bump invalidates results so deleted clients don't linger.
      ref.watch(clientsRefreshProvider);
      final repo = ref.watch(clientsRepositoryProvider);
      return repo.searchClients(query);
    });

/// Clients of one type, for the list's filter row. AutoDispose frees it as soon
/// as the filter is cleared.
final clientsByTypeProvider = FutureProvider.autoDispose
    .family<List<ClientRecord>, ClientType>((ref, type) async {
      ref.watch(clientsRefreshProvider);
      return ref.watch(clientsRepositoryProvider).fetchClientsByType(type);
    });

/// Archived clients, read from the same bounded cached window as search and
/// the type filter — so the Archived chip costs no extra read inside the TTL.
final archivedClientsProvider = FutureProvider.autoDispose<List<ClientRecord>>((
  ref,
) async {
  ref.watch(clientsRefreshProvider);
  return ref.watch(clientsRepositoryProvider).fetchArchivedClients();
});
