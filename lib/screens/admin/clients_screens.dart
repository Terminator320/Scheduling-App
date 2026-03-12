import 'package:flutter/material.dart';

import '../../models/client_record.dart';
import '../../utils/colors.dart';
import '../../widgets/admin_drawers.dart';

class AdminClientsPage extends StatefulWidget {
  const AdminClientsPage({super.key});

  @override
  State<AdminClientsPage> createState() => _AdminClientsPageState();
}

class _AdminClientsPageState extends State<AdminClientsPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ClientRecord> get filteredClients {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return kClients;
    return kClients.where((client) {
      return client.name.toLowerCase().contains(query) ||
          client.phone.toLowerCase().contains(query) ||
          client.email.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final clients = filteredClients;

    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      endDrawer: AdminMenuDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateClientPage(),
            ),
          );
          setState(() {});
        },
        backgroundColor: kPurple,
        shape: CircleBorder(),
        child: Icon(Icons.add, color: Colors.white, size: 30),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            children: [
              SizedBox(height: 10),
              Row(
                children: [
                  Spacer(),
                  Text(
                    'Edit Clients',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  Spacer(),
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Scaffold.of(context).openEndDrawer(),
                      child: Icon(Icons.menu, size: 28),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone number...',
                  hintStyle: TextStyle(color: Color(0xFF9A9A9A)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kPurple),
                  ),
                ),
              ),
              SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: clients.length,
                  separatorBuilder: (_, _) => SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final client = clients[index];
                    return _ClientCard(
                      client: client,
                      onEdit: () async {
                        await showEditClientPopup(context, client: client);
                        setState(() {});
                      },
                      onDelete: () {
                        setState(() {
                          kClients.remove(client);
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- CLIENTS DARK ---------------- */

class AdminClientsDarkPage extends StatefulWidget {
  const AdminClientsDarkPage({super.key});

  @override
  State<AdminClientsDarkPage> createState() => _AdminClientsDarkPageState();
}

class _AdminClientsDarkPageState extends State<AdminClientsDarkPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ClientRecord> get filteredClients {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return kClients;
    return kClients.where((client) {
      return client.name.toLowerCase().contains(query) ||
          client.phone.toLowerCase().contains(query) ||
          client.email.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final clients = filteredClients;

    return Scaffold(
      backgroundColor: Colors.black,
      endDrawer: const AdminMenuDrawerDark(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateClientDarkPage(),
            ),
          );
          setState(() {});
        },
        backgroundColor: kPurple,
        shape: CircleBorder(),
        child: Icon(Icons.add, color: Colors.white, size: 30),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            children: [
              SizedBox(height: 10),
              Row(
                children: [
                  Spacer(),
                  Text(
                    'Edit Clients',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Spacer(),
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Scaffold.of(context).openEndDrawer(),
                      child: Icon(Icons.menu, size: 28, color: Colors.white),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),
              TextField(
                controller: _searchController,
                style: TextStyle(color: Colors.white),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone number...',
                  hintStyle: TextStyle(color: Color(0xFF9A9A9A)),
                  filled: true,
                  fillColor: Color(0xFF171717),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Color(0xFF2D2D2D)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kPurple),
                  ),
                ),
              ),
              SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: clients.length,
                  separatorBuilder: (_, _) => SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final client = clients[index];
                    return _ClientCardDark(
                      client: client,
                      onEdit: () async {
                        await showEditClientDarkPopup(context, client: client);
                        setState(() {});
                      },
                      onDelete: () {
                        setState(() {
                          kClients.remove(client);
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- CREATE CLIENT LIGHT ---------------- */

class CreateClientPage extends StatefulWidget {
  const CreateClientPage({super.key});

  @override
  State<CreateClientPage> createState() => _CreateClientPageState();
}

class _CreateClientPageState extends State<CreateClientPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Add Client',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(width: 48),
                ],
              ),
              SizedBox(height: 18),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFFE0E0E0)),
                ),
                child: Column(
                  children: [
                    _clientFormField(controller: _nameController, hintText: 'name'),
                    SizedBox(height: 12),
                    _clientFormField(
                      controller: _addressController,
                      hintText: 'Address',
                      maxLines: 2,
                    ),
                    SizedBox(height: 12),
                    _clientFormField(controller: _phoneController, hintText: 'Phone number'),
                    SizedBox(height: 12),
                    _clientFormField(controller: _emailController, hintText: 'Email'),
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          kClients.add(
                            ClientRecord(
                              name: _nameController.text.trim().isEmpty
                                  ? 'Client name'
                                  : _nameController.text.trim(),
                              address: _addressController.text.trim().isEmpty
                                  ? '123 Main Street'
                                  : _addressController.text.trim(),
                              phone: _phoneController.text.trim().isEmpty
                                  ? '(514) 555-0000'
                                  : _phoneController.text.trim(),
                              email: _emailController.text.trim().isEmpty
                                  ? 'client@email.com'
                                  : _emailController.text.trim(),
                            ),
                          );
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text('Add Client'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- CREATE CLIENT DARK ---------------- */

class CreateClientDarkPage extends StatefulWidget {
  const CreateClientDarkPage({super.key});

  @override
  State<CreateClientDarkPage> createState() => _CreateClientDarkPageState();
}

class _CreateClientDarkPageState extends State<CreateClientDarkPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      'Add Client',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(width: 48),
                ],
              ),
              SizedBox(height: 18),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color(0xFF111111),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFF2A2A2A)),
                ),
                child: Column(
                  children: [
                    _clientFormFieldDark(controller: _nameController, hintText: 'name'),
                    SizedBox(height: 12),
                    _clientFormFieldDark(
                      controller: _addressController,
                      hintText: 'Address',
                      maxLines: 2,
                    ),
                    SizedBox(height: 12),
                    _clientFormFieldDark(controller: _phoneController, hintText: 'Phone number'),
                    SizedBox(height: 12),
                    _clientFormFieldDark(controller: _emailController, hintText: 'Email'),
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          kClients.add(
                            ClientRecord(
                              name: _nameController.text.trim().isEmpty
                                  ? 'Client name'
                                  : _nameController.text.trim(),
                              address: _addressController.text.trim().isEmpty
                                  ? '123 Main Street'
                                  : _addressController.text.trim(),
                              phone: _phoneController.text.trim().isEmpty
                                  ? '(514) 555-0000'
                                  : _phoneController.text.trim(),
                              email: _emailController.text.trim().isEmpty
                                  ? 'client@email.com'
                                  : _emailController.text.trim(),
                            ),
                          );
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text('Add Client'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  final ClientRecord client;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ClientCard({
    required this.client,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Color(0xFFDCD4F8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  client.phone,
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: Icon(Icons.edit_outlined, size: 20),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }
}

class _ClientCardDark extends StatelessWidget {
  final ClientRecord client;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ClientCardDark({
    required this.client,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Color(0xFF171717),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  client.phone,
                  style: TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: Icon(Icons.edit_outlined, size: 20, color: Colors.white70),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }
}

Widget _clientFormField({
  required TextEditingController controller,
  required String hintText,
  int maxLines = 1,
}) {
  return TextField(
    controller: controller,
    maxLines: maxLines,
    decoration: InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFFD8D8D8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kPurple),
      ),
    ),
  );
}

Widget _clientFormFieldDark({
  required TextEditingController controller,
  required String hintText,
  int maxLines = 1,
}) {
  return TextField(
    controller: controller,
    maxLines: maxLines,
    style: TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.white38),
      filled: true,
      fillColor: Color(0xFF171717),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFF2D2D2D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kPurple),
      ),
    ),
  );
}

Future<void> showEditClientPopup(
    BuildContext context, {
      required ClientRecord client,
    }) async {
  final nameController = TextEditingController(text: client.name);
  final addressController = TextEditingController(text: client.address);
  final phoneController = TextEditingController(text: client.phone);
  final emailController = TextEditingController(text: client.email);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                child: Divider(thickness: 4, color: Color(0xFFD0D0D0)),
              ),
              SizedBox(height: 12),
              Text(
                'Edit Client',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 18),
              _clientFormField(controller: nameController, hintText: 'name'),
              SizedBox(height: 12),
              _clientFormField(
                controller: addressController,
                hintText: 'Address',
                maxLines: 2,
              ),
              SizedBox(height: 12),
              _clientFormField(controller: phoneController, hintText: 'Phone number'),
              SizedBox(height: 12),
              _clientFormField(controller: emailController, hintText: 'Email'),
              SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    client.name = nameController.text.trim().isEmpty
                        ? client.name
                        : nameController.text.trim();
                    client.address = addressController.text.trim().isEmpty
                        ? client.address
                        : addressController.text.trim();
                    client.phone = phoneController.text.trim().isEmpty
                        ? client.phone
                        : phoneController.text.trim();
                    client.email = emailController.text.trim().isEmpty
                        ? client.email
                        : emailController.text.trim();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text('Update Client'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showEditClientDarkPopup(
    BuildContext context, {
      required ClientRecord client,
    }) async {
  final nameController = TextEditingController(text: client.name);
  final addressController = TextEditingController(text: client.address);
  final phoneController = TextEditingController(text: client.phone);
  final emailController = TextEditingController(text: client.email);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 22),
          decoration: BoxDecoration(
            color: Color(0xFF121212),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                child: Divider(thickness: 4, color: Color(0xFF3A3A3A)),
              ),
              SizedBox(height: 12),
              Text(
                'Edit Client',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 18),
              _clientFormFieldDark(controller: nameController, hintText: 'name'),
              SizedBox(height: 12),
              _clientFormFieldDark(
                controller: addressController,
                hintText: 'Address',
                maxLines: 2,
              ),
              SizedBox(height: 12),
              _clientFormFieldDark(controller: phoneController, hintText: 'Phone number'),
              SizedBox(height: 12),
              _clientFormFieldDark(controller: emailController, hintText: 'Email'),
              SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    client.name = nameController.text.trim().isEmpty
                        ? client.name
                        : nameController.text.trim();
                    client.address = addressController.text.trim().isEmpty
                        ? client.address
                        : addressController.text.trim();
                    client.phone = phoneController.text.trim().isEmpty
                        ? client.phone
                        : phoneController.text.trim();
                    client.email = emailController.text.trim().isEmpty
                        ? client.email
                        : emailController.text.trim();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text('Update Client'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}


/* ---------------- APPOINTMENTS LIGHT ---------------- */

