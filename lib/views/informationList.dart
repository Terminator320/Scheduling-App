import 'dart:async';
import 'package:flutter/material.dart';

import '../models/appointment_record.dart';
import '../models/client_record.dart';
import '../services/appointment_service.dart';
import '../services/client_service.dart';
import '../utils/calendar_utils/sheet_helpers.dart';
import '../widgets/form_widgets/form_helpers.dart';
import '../widgets/list_widgets/appointment_tile.dart';
import '../widgets/list_widgets/client_tile.dart';
import '../widgets/popup_widgets/add_client_sheet.dart';
import '../widgets/settings_drawer.dart';

enum ListMode { clients, appointments }

class ListInformation extends StatefulWidget {
  final String mode;
  final bool isAdmin;
  final String employeeId;

  const ListInformation({
    super.key,
    required this.mode,
    required this.isAdmin,
    required this.employeeId,
  });

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
    _scrollController.dispose();
    _clientsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _onAddAppointment() async {
    final newEvent = await showAddEventPopup(context);
    if (newEvent != null) {
      await _appointmentService.addAppointment(newEvent);
    }
  }

  void _onAddClient() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddClientSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title), centerTitle: true),
      endDrawer: SettingsDrawer(
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = _searchController.text.trim().toLowerCase();

    final filtered = query.isEmpty
        ? _allClients
        : _allClients.where((c) {
            return c.displayName.toLowerCase().contains(query) ||
                c.phone.contains(query);
          }).toList();

    final displayed = filtered.length > _displayLimit
        ? filtered.sublist(0, _displayLimit)
        : filtered;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: formInputDecoration(
              context,
              'Search by name or phone...',
            ).copyWith(
              prefixIcon: Icon(
                Icons.search,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      onPressed: () =>
                          setState(() => _searchController.clear()),
                      tooltip: 'Clear',
                    )
                  : null,
            ),
          ),
        ),
        Expanded(
          child: displayed.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        query.isEmpty
                            ? Icons.groups_outlined
                            : Icons.search_off_outlined,
                        size: 40,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        query.isEmpty
                            ? 'No clients yet'
                            : 'No clients match "$query"',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: displayed.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ClientTile(client: displayed[index]),
                  ),
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
          return const Center(child: Text('No appointments found.'));
        }

        final sorted = [...appointments]
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) =>
              AppointmentTile(appointment: sorted[index]),
        );
      },
    );
  }
}
