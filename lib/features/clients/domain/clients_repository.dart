import 'package:scheduling/features/clients/domain/models/client_record.dart';

abstract class ClientsRepository {
  Stream<List<ClientRecord>> watchClients({int? limit});

  Future<ClientRecord?> getClientById(String id);

  Future<void> addClient(ClientRecord client);

  Future<void> updateClient(ClientRecord client);

  Future<void> deleteClient(String id);

  Future<List<ClientRecord>> searchClients(String query);
}
