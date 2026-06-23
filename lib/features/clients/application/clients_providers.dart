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

/// Bumped after any client add/update/delete so the paginated clients list
/// (which no longer streams) can refresh itself. Replaces the previous live
/// `watchClients` stream's auto-update behavior.
final clientsRefreshProvider = NotifierProvider<ClientsRefresh, int>(
  ClientsRefresh.new,
);

class ClientsRefresh extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Comprehensive client search: reads up to [ClientSearchPolicy.serverReadLimit]
/// docs and matches across all fields (name, business name, email, address,
/// contacts, phone) with relevance scoring — unlike the loaded-page filter, it
/// finds clients regardless of which page they're on. AutoDispose so each
/// distinct query instance is freed once no longer watched.
final clientSearchProvider = FutureProvider.autoDispose
    .family<List<ClientRecord>, String>((
      ref,
      query,
    ) async {
      if (!ClientSearchPolicy.shouldSearch(query)) return const [];
      final repo = ref.watch(clientsRepositoryProvider);
      return repo.searchClients(query);
    });
