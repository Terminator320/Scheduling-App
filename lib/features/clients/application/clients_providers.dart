import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/clients/data/firebase_clients_repository.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
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

/// Comprehensive client search with relevance scoring; autoDispose frees results per query instance.
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
