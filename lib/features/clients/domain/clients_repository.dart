import 'package:scheduling/features/clients/domain/models/client_record.dart';

abstract class ClientsRepository {
  Stream<List<ClientRecord>> watchClients({int? limit});

  Future<ClientRecord?> getClientById(String id);

  Future<void> addClient(ClientRecord client);

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
}
