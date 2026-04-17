import 'package:flutter/material.dart';

import '../models/appointment_record.dart';
import '../models/client_record.dart';
import '../services/client_service.dart';
import '../services/appointment_service.dart';

import '../utils/date_utils_helper.dart';

import '../widgets/settings_drawer.dart';

import '../widgets/popup_widgets/details_edit_sheet.dart';

enum ListMode { clients, appointments }

class ListInformation extends StatefulWidget {
  final String mode;

  const ListInformation({super.key, required this.mode});

  @override
  State<ListInformation> createState() => _ListInformationState();
}

class _ListInformationState extends State<ListInformation> {
  final ClientService _clientService = ClientService();
  final AppointmentService _appointmentService = AppointmentService();

  bool get _isClients => widget.mode == 'Clients';

  String get _title => _isClients ? 'Clients' : 'Appointments';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title), centerTitle: true),
      endDrawer: const SettingsDrawer(),
      body: _isClients ? _buildClientList() : _buildAppointmentList(),
    );
  }

  Widget _buildClientList() {
    return StreamBuilder<List<ClientRecord>>(
      stream: _clientService.clientsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error : ${snapshot.error}'));
        }

        final clients = snapshot.data ?? [];

        if (clients.isEmpty) {
          return const Center(child: Text('Any clients founded.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: clients.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final client = clients[index];
            return _ClientTile(client: client);
          },
        );
      },
    );
  }

  Widget _buildAppointmentList() {
    return StreamBuilder<List<AppointmentRecord>>(
      stream: _appointmentService.getAllAppointments(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error : ${snapshot.error}'));
        }

        final appointments = snapshot.data ?? [];

        if (appointments.isEmpty) {
          return const Center(child: Text('Any appointments founded.'));
        }

        // Sort by startTime ascending
        final sorted = [...appointments]
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final appointment = sorted[index];
            return _AppointmentTile(appointment: appointment);
          },
        );
      },
    );
  }
}

class _ClientTile extends StatelessWidget {
  final ClientRecord client;

  const _ClientTile({required this.client});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => _ClientDetailSheet(client: client),
          );
        },
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            client.displayName.isNotEmpty
                ? client.displayName[0].toUpperCase()
                : '?',
            style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
        title: Text(
          client.displayName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (client.phone.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.phone, size: 13),
                  const SizedBox(width: 4),
                  Text(client.phone),
                ],
              ),
            if (client.address.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.location_on, size: 13),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      client.address,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        ),
        isThreeLine: client.address.isNotEmpty && client.phone.isNotEmpty,
      ),
    );
  }
}

class _ClientDetailSheet extends StatefulWidget {
  final ClientRecord client;

  const _ClientDetailSheet({required this.client});

  @override
  State<_ClientDetailSheet> createState() => _ClientDetailSheetState();
}

class _ClientDetailSheetState extends State<_ClientDetailSheet> {
  bool _isEditing = false;
  final Map<String, String?> _errors = {};

  late final TextEditingController _businessNameController;
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;

  final _clientService = ClientService();

  @override
  void initState() {
    super.initState();
    final c = widget.client;
    _businessNameController = TextEditingController(text: c.businessName);
    _nameController        = TextEditingController(text: c.name);
    _phoneController       = TextEditingController(text: c.phone);
    _emailController       = TextEditingController(text: c.email);
    _addressController     = TextEditingController(text: c.address);
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _cancelEdit() {
    final c = widget.client;
    setState(() {
      _isEditing = false;
      _businessNameController.text = c.businessName;
      _nameController.text         = c.name;
      _phoneController.text        = c.phone;
      _emailController.text        = c.email;
      _addressController.text      = c.address;
      _errors.clear();
    });
  }

  Future<void> _save() async {
    setState(() {
      _errors['businessName'] = _businessNameController.text.trim().isEmpty
          ? "Business name is required" : null;
      _errors['name'] = _nameController.text.trim().isEmpty
          ? "Name is required" : null;
      _errors['phone'] = _phoneController.text.trim().isEmpty
          ? "Phone is required" : null;
      _errors['email'] = _emailController.text.trim().isEmpty
          ? "Email is required" : null;
      _errors['address'] = _addressController.text.trim().isEmpty
          ? "Address is required" : null;
    });

    if (_errors.values.any((e) => e != null)) return;

    final updated = ClientRecord(
      id:           widget.client.id,
      businessName: _businessNameController.text.trim(),
      name:         _nameController.text.trim(),
      phone:        _phoneController.text.trim(),
      email:        _emailController.text.trim(),
      address:      _addressController.text.trim(),
      contacts:     widget.client.contacts,
    );

    await _clientService.updateClient(updated);
    if (mounted) setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (sheetContext, scrollController) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(sheetContext).unfocus(),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 60,
              ),
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

                // Header
                _isEditing
                    ? Text("Edit client",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge)
                    : _buildViewHeader(theme),

                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Contenu : vue ou édition
                if (_isEditing)
                  ..._buildEditFields(theme)
                else
                  ..._buildViewFields(theme),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                _buildActionButtons(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Header vue ──────────────────────────────────────────────────
  Widget _buildViewHeader(ThemeData theme) {
    final c = widget.client;
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            c.displayName.isNotEmpty ? c.displayName[0].toUpperCase() : '?',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.displayName,
                  style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold)),
              if (c.name.isNotEmpty && c.name != c.displayName)
                Text(c.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6))),
            ],
          ),
        ),
      ],
    );
  }

  // ── Champs vue ──────────────────────────────────────────────────
  List<Widget> _buildViewFields(ThemeData theme) {
    final c = widget.client;
    return [
      if (c.phone.isNotEmpty)   _InfoRow(icon: Icons.phone,       text: c.phone),
      if (c.email.isNotEmpty)   _InfoRow(icon: Icons.email,       text: c.email),
      if (c.address.isNotEmpty) _InfoRow(icon: Icons.location_on, text: c.address),

      if (c.contacts.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('Contacts',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ...c.contacts.map((contact) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          color: theme.colorScheme.surfaceVariant,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(icon: Icons.person_outline,  text: contact.name),
                _InfoRow(icon: Icons.phone_outlined,  text: contact.phone),
                _InfoRow(icon: Icons.mail_outline,    text: contact.email),
              ],
            ),
          ),
        )),
      ],
    ];
  }

  // ── Champs édition ───────────────────────────────────────────────
  List<Widget> _buildEditFields(ThemeData theme) {
    return [
      _editField("Business name", _businessNameController,
          error: _errors['businessName'],
          onChanged: (_) => setState(() => _errors['businessName'] = null)),
      const SizedBox(height: 14),
      _editField("Contact name", _nameController,
          error: _errors['name'],
          onChanged: (_) => setState(() => _errors['name'] = null)),
      const SizedBox(height: 14),
      _editField("Phone", _phoneController,
          keyboard: TextInputType.phone,
          error: _errors['phone'],
          onChanged: (_) => setState(() => _errors['phone'] = null)),
      const SizedBox(height: 14),
      _editField("Email", _emailController,
          keyboard: TextInputType.emailAddress,
          error: _errors['email'],
          onChanged: (_) => setState(() => _errors['email'] = null)),
      const SizedBox(height: 14),
      _editField("Address", _addressController,
          error: _errors['address'],
          onChanged: (_) => setState(() => _errors['address'] = null)),
    ];
  }

  Widget _editField(
      String label,
      TextEditingController controller, {
        String? error,
        TextInputType keyboard = TextInputType.text,
        void Function(String)? onChanged,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboard,
          onChanged: onChanged,
          decoration: InputDecoration(
            errorText: error,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  // ── Boutons d'action ─────────────────────────────────────────────
  Widget _buildActionButtons() {
    if (_isEditing) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _cancelEdit,
              child: const Text("Cancel"),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _save,
              child: const Text("Save changes"),
            ),
          ),
        ],
      );
    }

    // Mode vue
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context),
            child: Icon(Icons.close),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => setState(() => _isEditing = true),
            child: Icon(Icons.edit),
          ),
        ),
      ],
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  final AppointmentRecord appointment;

  const _AppointmentTile({required this.appointment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => EventDetailsSheet(appointment: appointment),
          );
        },
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateUtilsHelper.formatPrettyDate(appointment.startTime),
              style: theme.textTheme.labelMedium,
            ),
          ],
        ),
        title: Text(
          appointment.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, size: 13),
                const SizedBox(width: 4),
                Text(appointment.clientName),
              ],
            ),
            if (appointment.employeeNames.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.group, size: 13),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      appointment.employeeNames.join(', '),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        ),
        isThreeLine: appointment.employeeNames.isNotEmpty,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
