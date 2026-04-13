import 'package:flutter/material.dart';

import '../models/appointment_record.dart';
import '../models/client_record.dart';
import '../services/client_service.dart';
import '../services/appointment_service.dart';

import '../widgets/settings_drawer.dart';

enum ListMode { clients, appointments }

class ListInformation extends StatefulWidget {
  final ListMode mode;

  const ListInformation({super.key, required this.mode});

  @override
  State<ListInformation> createState() => _ListInformationState();
}

class _ListInformationState extends State<ListInformation> {
  final ClientService _clientService = ClientService();
  final AppointmentService _appointmentService = AppointmentService();

  bool get _isClients => widget.mode == ListMode.clients;

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

  // Status → colour mapping
  Color _statusColor(BuildContext context, String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'completed':
        return Colors.blue;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(context, appointment.status);

    return Card(
      child: ListTile(
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _formatDate(appointment.startTime),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              _formatTime(appointment.startTime),
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
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor, width: 1),
          ),
          child: Text(
            appointment.status,
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
