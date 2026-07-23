import 'package:scheduling/features/clients/domain/models/client_record.dart';

abstract class ClientsRepository {
  Future<ClientRecord?> getClientById(String id);

  /// Persists new client and returns it with generated Firestore doc id for caller linking.
  Future<ClientRecord> addClient(ClientRecord client);

  Future<void> updateClient(ClientRecord client);

  Future<void> deleteClient(String id);

  Future<List<ClientRecord>> searchClients(String query);

  /// Fetches next page of clients (newest-first); pass previous page's last item as [after], null for first page.
  Future<List<ClientRecord>> fetchClientsPage({
    required int limit,
    ClientRecord? after,
  });

  /// One-shot fetch of clients created since [since] for dashboard trends; legacy docs without `createdAt` excluded (old imports).
  Future<List<ClientRecord>> fetchClientsCreatedSince(DateTime since);
}
