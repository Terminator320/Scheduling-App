
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

/// Streams all clients from Firestore, deduplicated across screens watching
/// the same provider. Used by the clients list and by appointment creation
/// (Phase 3 — calendar — will switch to this).
final clientsStreamProvider = StreamProvider<List<ClientRecord>>((ref) {
  final repo = ref.watch(clientsRepositoryProvider);
  return repo.watchClients();
});

/// Filters the watched client list by a free-text query without re-querying
/// Firestore. Mirrors the lightweight client-side filter the original screen
/// used (`displayName.toLowerCase().contains(query) || phone.contains(query)`).
///
/// Family-keyed by the trimmed lower-cased query so that selecting the same
/// query from multiple widgets shares the computation.
final filteredClientsProvider = Provider.family<List<ClientRecord>, String>((
  ref,
  query,
) {
  final list = ref.watch(clientsStreamProvider).asData?.value ?? const [];
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return list;
  return list
      .where(
        (c) =>
            c.displayName.toLowerCase().contains(q) || c.phone.contains(q),
      )
      .toList();
});

/// Server-side scored search. Returns an empty list when
/// `ClientSearchPolicy.shouldSearch` rejects the query — caller does not
/// need to debounce or pre-validate.
final clientSearchProvider =
    FutureProvider.family<List<ClientRecord>, String>((ref, query) async {
      if (!ClientSearchPolicy.shouldSearch(query)) return const [];
      final repo = ref.watch(clientsRepositoryProvider);
      return repo.searchClients(query);
    });
