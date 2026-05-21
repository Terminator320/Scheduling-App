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

final clientsStreamProvider = StreamProvider<List<ClientRecord>>((ref) {
  final repo = ref.watch(clientsRepositoryProvider);
  return repo.watchClients();
});

final filteredClientsProvider = Provider.family<List<ClientRecord>, String>((
  ref,
  query,
) {
  final list = ref.watch(clientsStreamProvider).asData?.value ?? const [];
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return list;
  return list
      .where(
        (c) => c.displayName.toLowerCase().contains(q) || c.phone.contains(q),
      )
      .toList();
});

final clientSearchProvider = FutureProvider.family<List<ClientRecord>, String>((
  ref,
  query,
) async {
  if (!ClientSearchPolicy.shouldSearch(query)) return const [];
  final repo = ref.watch(clientsRepositoryProvider);
  return repo.searchClients(query);
});
