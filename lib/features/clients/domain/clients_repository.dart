import 'package:scheduling/features/clients/domain/models/client_record.dart';

/// Repository contract for the `clients` collection. Pure Dart — no Firebase
/// imports. Implementations live under `data/`.
///
/// Mockable in tests via `mocktail` so feature logic can be exercised without
/// a Firebase emulator.
abstract class ClientsRepository {
  Stream<List<ClientRecord>> watchClients({int? limit});

  Future<ClientRecord?> getClientById(String id);

  /// Add a new client. Implementation MUST set `createdAt` and `updatedAt`
  /// to `serverTimestamp` (CLAUDE.md invariant). Email fields MUST be
  /// trimmed + lower-cased before write (email normalization invariant).
  Future<void> addClient(ClientRecord client);

  /// Update an existing client. Implementation MUST set `updatedAt` to
  /// `serverTimestamp`. Email fields MUST be normalized.
  Future<void> updateClient(ClientRecord client);

  Future<void> deleteClient(String id);

  /// Run a scored search using `ClientSearchPolicy`. Returns the top
  /// `ClientSearchPolicy.resultDisplayLimit` matches sorted by score then by
  /// display name.
  Future<List<ClientRecord>> searchClients(String query);
}
