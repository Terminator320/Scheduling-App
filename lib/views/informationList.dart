import 'package:flutter/material.dart';
import 'dart:async';
import '../models/appointment_record.dart';
import '../models/client_record.dart';
import '../services/client_service.dart';
import '../services/appointment_service.dart';

import '../utils/calendar_utils/sheet_helpers.dart';
import '../utils/date_utils_helper.dart';

import '../widgets/settings_drawer.dart';

import '../widgets/popup_widgets/details_edit_sheet.dart';

import '../widgets/client_search_field.dart';

enum ListMode { clients, appointments }

class ListInformation extends StatefulWidget {
  final String mode;
  final bool isAdmin;
  final String employeeId;


  const ListInformation({super.key, required this.mode, required this.isAdmin,required this.employeeId,});

  @override
  State<ListInformation> createState() => _ListInformationState();
}

class _ListInformationState extends State<ListInformation> {

  int _displayLimit = 50;
  final ScrollController _scrollController = ScrollController();

  final TextEditingController _searchController = TextEditingController();
  List<ClientRecord> _allClients = [];
  final ClientService _clientService = ClientService();
  final AppointmentService _appointmentService = AppointmentService();
  StreamSubscription? _clientsSubscription;

  bool get _isClients => widget.mode == 'Clients';

  String get _title => _isClients ? 'Clients' : 'Appointments';

  @override
  void initState() {
    super.initState();
    _clientsSubscription = _clientService.clientsStream().listen((clients) {
      if (mounted) setState(() => _allClients = clients);
    });

    //Limit at 50 client displayed
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        setState(() => _displayLimit += 50);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _clientsSubscription?.cancel();
    super.dispose();
  }

  // ── FAB handlers ────────────────────────────────────────────────

  /// Même logique que dans MainCalendar : ouvre le popup d'ajout
  /// d'appointment et sauvegarde via AppointmentService.
  Future<void> _onAddAppointment() async {
    final newEvent = await showAddEventPopup(context);
    if (newEvent != null) {
      await _appointmentService.addAppointment(newEvent);
    }
  }

  /// Ouvre le popup d'ajout de client.
  /// Remplace le corps par ton propre widget d'ajout si disponible.
  Future<void> _onAddClient() async {
    // TODO: remplacer par showAddClientPopup(context) quand disponible
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddClientSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title), centerTitle: true),
      endDrawer: SettingsDrawer(isAdmin: widget.isAdmin, employeeId: widget.employeeId,),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
              onPressed: _isClients ? _onAddClient : _onAddAppointment,
              child: const Icon(Icons.add),
            )
          : null,
      body: _isClients ? _buildClientList() : _buildAppointmentList(),
    );
  }

  Widget _buildClientList() {
    final query = _searchController.text.trim().toLowerCase();

    final displayed = query.isEmpty
        ? _allClients
        : _allClients.where((c) {
            return c.displayName.toLowerCase().contains(query) ||
                c.phone.contains(query);
          }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by name or phone...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
        Expanded(
          child: displayed.isEmpty
              ? const Center(child: Text('Aucun client trouvé.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: displayed.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return _ClientTile(client: displayed[index]);
                  },
                ),
        ),
      ],
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

// ── Placeholder sheet d'ajout de client ─────────────────────────
// À remplacer par ton vrai widget quand il sera prêt.
class _AddClientSheet extends StatefulWidget {
  const _AddClientSheet();

  @override
  State<_AddClientSheet> createState() => _AddClientSheetState();
}

class _AddClientSheetState extends State<_AddClientSheet> {
  final _businessNameController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _clientService = ClientService();
  final Map<String, String?> _errors = {};

  @override
  void dispose() {
    _businessNameController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _errors['businessName'] = _businessNameController.text.trim().isEmpty
          ? "Business name is required"
          : null;
      _errors['name'] = _nameController.text.trim().isEmpty
          ? "Name is required"
          : null;
      _errors['phone'] = _phoneController.text.trim().isEmpty
          ? "Phone is required"
          : null;
    });

    if (_errors.values.any((e) => e != null)) return;

    final newClient = ClientRecord(
      id: '',
      businessName: _businessNameController.text.trim(),
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      address: _addressController.text.trim(),
      contacts: [],
    );

    await _clientService.addClient(newClient);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text("New client", style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _field(
              "Business name",
              _businessNameController,
              error: _errors['businessName'],
            ),
            const SizedBox(height: 14),
            _field("Contact name", _nameController, error: _errors['name']),
            const SizedBox(height: 14),
            _field(
              "Phone",
              _phoneController,
              error: _errors['phone'],
              keyboard: TextInputType.phone,
            ),
            const SizedBox(height: 14),
            _field(
              "Email",
              _emailController,
              keyboard: TextInputType.emailAddress,
            ),
            const SizedBox(height: 14),
            _field("Address", _addressController),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Icon(Icons.close),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    child: const Text("Add"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? error,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: keyboard,
          onChanged: (_) => setState(() => _errors[label] = null),
          decoration: InputDecoration(
            errorText: error,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ],
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
          showModalBottomSheet(
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
    _nameController = TextEditingController(text: c.name);
    _phoneController = TextEditingController(text: c.phone);
    _emailController = TextEditingController(text: c.email);
    _addressController = TextEditingController(text: c.address);
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
      _nameController.text = c.name;
      _phoneController.text = c.phone;
      _emailController.text = c.email;
      _addressController.text = c.address;
      _errors.clear();
    });
  }

  Future<void> _save() async {
    setState(() {
      _errors['businessName'] = _businessNameController.text.trim().isEmpty
          ? "Business name is required"
          : null;
      _errors['name'] = _nameController.text.trim().isEmpty
          ? "Name is required"
          : null;
      _errors['phone'] = _phoneController.text.trim().isEmpty
          ? "Phone is required"
          : null;
      _errors['email'] = _emailController.text.trim().isEmpty
          ? "Email is required"
          : null;
      _errors['address'] = _addressController.text.trim().isEmpty
          ? "Address is required"
          : null;
    });

    if (_errors.values.any((e) => e != null)) return;

    final updated = ClientRecord(
      id: widget.client.id,
      businessName: _businessNameController.text.trim(),
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      address: _addressController.text.trim(),
      contacts: widget.client.contacts,
    );

    await _clientService.updateClient(updated);
    if (mounted) setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              _isEditing
                  ? Text(
                      "Edit client",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    )
                  : _buildViewHeader(theme),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 16),
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
      ),
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
              Text(
                c.displayName,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (c.name.isNotEmpty && c.name != c.displayName)
                Text(
                  c.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
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
      if (c.phone.isNotEmpty) _InfoRow(icon: Icons.phone, text: c.phone),
      if (c.email.isNotEmpty) _InfoRow(icon: Icons.email, text: c.email),
      if (c.address.isNotEmpty)
        _InfoRow(icon: Icons.location_on, text: c.address),

      if (c.contacts.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(
          'Contacts',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ...c.contacts.map(
          (contact) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            color: theme.colorScheme.surfaceVariant,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(icon: Icons.person_outline, text: contact.name),
                  _InfoRow(icon: Icons.phone_outlined, text: contact.phone),
                  _InfoRow(icon: Icons.mail_outline, text: contact.email),
                ],
              ),
            ),
          ),
        ),
      ],
    ];
  }

  // ── Champs édition ───────────────────────────────────────────────
  List<Widget> _buildEditFields(ThemeData theme) {
    return [
      _editField(
        "Business name",
        _businessNameController,
        error: _errors['businessName'],
        onChanged: (_) => setState(() => _errors['businessName'] = null),
      ),
      const SizedBox(height: 14),
      _editField(
        "Contact name",
        _nameController,
        error: _errors['name'],
        onChanged: (_) => setState(() => _errors['name'] = null),
      ),
      const SizedBox(height: 14),
      _editField(
        "Phone",
        _phoneController,
        keyboard: TextInputType.phone,
        error: _errors['phone'],
        onChanged: (_) => setState(() => _errors['phone'] = null),
      ),
      const SizedBox(height: 14),
      _editField(
        "Email",
        _emailController,
        keyboard: TextInputType.emailAddress,
        error: _errors['email'],
        onChanged: (_) => setState(() => _errors['email'] = null),
      ),
      const SizedBox(height: 14),
      _editField(
        "Address",
        _addressController,
        error: _errors['address'],
        onChanged: (_) => setState(() => _errors['address'] = null),
      ),
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
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboard,
          onChanged: onChanged,
          decoration: InputDecoration(
            errorText: error,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
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
                  borderRadius: BorderRadius.circular(10),
                ),
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
                  borderRadius: BorderRadius.circular(10),
                ),
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
                borderRadius: BorderRadius.circular(10),
              ),
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
                borderRadius: BorderRadius.circular(10),
              ),
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
