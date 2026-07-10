import 'package:scheduling/features/clients/domain/models/client_record.dart';

abstract class ClientsRepository {
  Future<ClientRecord?> getClientById(String id);

  /// Persists a new client and returns it with the generated Firestore doc id
  /// populated, so callers (e.g. inline add during appointment booking) can
  /// link to it immediately.
  Future<ClientRecord> addClient(ClientRecord client);

  Future<void> updateClient(ClientRecord client);

  Future<void> deleteClient(String id);

  Future<List<ClientRecord>> searchClients(String query);

  /// Fetches one page of clients ordered newest-first. Pass the last item of
  /// the previously loaded page as [after] to fetch the following page; pass
  /// null for the first page. A returned list shorter than [limit] means the
  /// end has been reached.
  Future<List<ClientRecord>> fetchClientsPage({
    required int limit,
    ClientRecord? after,
  });

  /// One-shot fetch of clients created at or after [since] (dashboard
  /// new-clients trend). Legacy docs without `createdAt` are excluded by the
  /// orderBy — an accepted undercount (they're old imports anyway).
  Future<List<ClientRecord>> fetchClientsCreatedSince(DateTime since);
}
