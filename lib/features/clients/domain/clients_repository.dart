import 'package:scheduling/features/clients/domain/models/client_record.dart';

abstract class ClientsRepository {
  Future<ClientRecord?> getClientById(String id);

  /// Persists a new client and returns it with the generated Firestore doc id, so the
  /// caller can link to it right away.
  Future<ClientRecord> addClient(ClientRecord client);

  Future<void> updateClient(ClientRecord client);

  Future<List<ClientRecord>> searchClients(String query);

  /// Fetches the next page of clients, newest first. Pass the previous page's last item
  /// as [after], or null for the first page.
  Future<List<ClientRecord>> fetchClientsPage({
    required int limit,
    ClientRecord? after,
  });

  /// One-shot fetch of clients created since [since], used for dashboard trends. Legacy
  /// docs without `createdAt` (old imports) are excluded.
  Future<List<ClientRecord>> fetchClientsCreatedSince(DateTime since);

  /// Every distinct tag in use, sorted, for the clients list's filter row.
  ///
  /// Read from the same bounded, cached window `searchClients` scans, so the
  /// filter row costs no extra read inside the TTL.
  Future<List<String>> fetchClientTags();

  /// Clients carrying [tag], name-sorted, from that same window.
  ///
  /// A SEPARATE bounded read, deliberately not a filter over `fetchClientsPage`:
  /// filtering a server page in Dart shortens a page the server actually filled,
  /// which stops the paginated list early. See the "never removed" invariant in
  /// CLAUDE.md for the full reasoning.
  Future<List<ClientRecord>> fetchClientsByTag(String tag);
}
