class ClientRecord {
  ClientRecord({
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
  });

  String name;
  String phone;
  String email;
  String address;
}

final List<ClientRecord> kClients = [
  ClientRecord(
    name: 'Client name',
    phone: '(514) 555-0112',
    email: 'client@email.com',
    address: '123 Main Street',
  ),
  ClientRecord(
    name: 'Client name',
    phone: '(514) 555-0135',
    email: 'client@email.com',
    address: '123 Main Street',
  ),
  ClientRecord(
    name: 'Client name',
    phone: '(514) 555-0174',
    email: 'client@email.com',
    address: '123 Main Street',
  ),
  ClientRecord(
    name: 'Client name',
    phone: '(514) 555-0180',
    email: 'client@email.com',
    address: '123 Main Street',
  ),
  ClientRecord(
    name: 'Client name',
    phone: '(514) 555-0193',
    email: 'client@email.com',
    address: '123 Main Street',
  ),
];

