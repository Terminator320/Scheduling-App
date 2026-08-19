import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';

abstract class ClientsRepository {
  Future<ClientRecord?> getClientById(String id);

  /// Live stream of one client doc; emits null once the doc is gone.
  ///
  /// The Wave sync badge is why this exists and why it cannot be a one-shot
  /// read. `wave.syncState` is written ONLY by Cloud Functions — the
  /// `waveUpsertCustomer` trigger stamps `pending` after the save has already
  /// returned, and the outbox worker flips it to `synced` up to five minutes
  /// later — so any record a screen was handed necessarily predates the state
  /// the badge is trying to show. See the sync-badge invariant in CLAUDE.md.
  Stream<ClientRecord?> watchClient(String id);

  /// Persists a new client and returns it with the generated Firestore doc id, so the
  /// caller can link to it right away.
  Future<ClientRecord> addClient(ClientRecord client);

  Future<void> updateClient(ClientRecord client);

  /// Deletes a client. Refuses (throws `ClientsFailureHasHistory`) when the
  /// client still has appointments — the server re-checks with a live count()
  /// aggregate and is the real boundary. Archive is the normal removal.
  Future<void> deleteClient(String id);

  /// Archives or un-archives a client. Archived clients drop out of the
  /// paginated list and the type filter but stay searchable and stay bookable —
  /// their `clientId` links on existing appointments are untouched.
  Future<void> setClientArchived(String id, {required bool archived});

  /// Archived clients, name-sorted, from the same cached window
  /// `searchClients` scans — so the Archived chip costs no extra read inside
  /// the TTL and needs no composite index.
  Future<List<ClientRecord>> fetchArchivedClients();

  Future<List<ClientRecord>> searchClients(String query);

  /// Fetches the next page of clients, newest first. Pass the previous page's last item
  /// as [after], or null for the first page.
  Future<List<ClientRecord>> fetchClientsPage({
    required int limit,
    ClientRecord? after,
  });

  /// One-shot fetch of clients created since [since], used for dashboard
  /// trends. Legacy docs without `createdAt` (old imports) are excluded.
  Future<List<ClientRecord>> fetchClientsCreatedSince(DateTime since);

  /// Clients of [type], name-sorted, from the same cached window
  /// `searchClients` scans — so the filter costs no extra read inside the TTL
  /// and needs no composite index.
  ///
  /// A SEPARATE bounded read, deliberately not a filter over `fetchClientsPage`:
  /// filtering a server page in Dart shortens a page the server actually filled,
  /// which stops the paginated list early. See the "never removed" invariant in
  /// CLAUDE.md for the full reasoning.
  Future<List<ClientRecord>> fetchClientsByType(ClientType type);
}
