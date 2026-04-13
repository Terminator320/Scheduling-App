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
          return Center(child: Text('Erreur : ${snapshot.error}'));
        }

        final clients = snapshot.data ?? [];

        if (clients.isEmpty) {
          return const Center(child: Text('Aucun client trouvé.'));
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
          return Center(child: Text('Erreur : ${snapshot.error}'));
        }

        final appointments = snapshot.data ?? [];

        if (appointments.isEmpty) {
          return const Center(child: Text('Aucun rendez-vous trouvé.'));
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

class _AppointmentTile extends StatelessWidget {
  final AppointmentRecord appointment;


  const _AppointmentTile({required this.appointment});

  EventDetailsSheet popupClient = EventDetailsSheet(appointment: appointment);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
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
