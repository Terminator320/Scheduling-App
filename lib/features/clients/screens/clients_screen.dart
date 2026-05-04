import 'dart:async';
import 'package:flutter/material.dart';

import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/calendar/services/appointment_service.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/appointment_tile.dart';
import 'package:scheduling/features/clients/models/client_record.dart';
import 'package:scheduling/features/clients/services/client_service.dart';
import 'package:scheduling/features/clients/widgets/add_client_sheet.dart';
import 'package:scheduling/features/clients/widgets/client_detail_sheet.dart';
import 'package:scheduling/features/clients/widgets/client_tile.dart';
import 'package:scheduling/features/settings/widgets/settings_drawer.dart';
import 'package:scheduling/shared/widgets/appScaffoldBar.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';

import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/features/employees/services/user_service.dart';

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
  final TextEditingController _appointmentSearchController =
      TextEditingController();
  List<ClientRecord> _allClients = [];
  final ClientService _clientService = ClientService();
  final AppointmentService _appointmentService = AppointmentService();
  StreamSubscription? _clientsSubscription;
  final UserService _userService = UserService();
  List<EmployeeRecord> _allEmployees = [];
  StreamSubscription? _employeesSubscription;


  bool get _isClients => widget.mode == 'Clients';

  String get _title => _isClients ? 'Clients' : 'Appointments';

  @override
  void initState() {
    super.initState();
    _userService.allUsersStream().listen((data) {
      if (mounted) setState(() => _allEmployees = data);
    });
    _clientsSubscription = _clientService.clientsStream().listen((clients) {
      if (mounted) setState(() => _allClients = clients);
    });
    _employeesSubscription = _userService.allUsersStream().listen((data) {
      if (mounted) setState(() => _allEmployees = data);
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
    _appointmentSearchController.dispose();
    _scrollController.dispose();
    _clientsSubscription?.cancel();
    _employeesSubscription?.cancel();
    super.dispose();
  }

  void _onAddClient() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddClientSheet(),
    );
  }

  void _clearClientSearch() {
    // Cancel search before opening a result so the list returns cleanly.
    FocusManager.instance.primaryFocus?.unfocus();
    if (_searchController.text.isEmpty) return;
    setState(() => _searchController.clear());
  }

  void _clearAppointmentSearch() {
    // Cancel search before opening a result so the list returns cleanly.
    FocusManager.instance.primaryFocus?.unfocus();
    if (_appointmentSearchController.text.isEmpty) return;
    setState(() => _appointmentSearchController.clear());
  }

  Future<void> _settleSearchBeforeSheet() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  Future<void> _unfocusAfterSheetClose() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _openClientFromSearch(ClientRecord client) async {
    _clearClientSearch();
    await _settleSearchBeforeSheet();
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ClientDetailSheet(client: client),
    );

    if (mounted) await _unfocusAfterSheetClose();
  }

  Future<void> _openAppointmentFromSearch(AppointmentRecord appointment) async {
    _clearAppointmentSearch();
    await _settleSearchBeforeSheet();
    if (!mounted) return;

    await showEventDetails(context, appointment, showActions: false);

    if (mounted) await _unfocusAfterSheetClose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appScaffoldBar(context, _title, widget.employeeId, widget.isAdmin),
      endDrawer: SettingsDrawer(
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
      floatingActionButton: widget.isAdmin && _isClients
          ? FloatingActionButton(
              onPressed: _onAddClient,
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
            // Close the keyboard after the user submits a search.
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration:
                formInputDecoration(
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
                    child: ClientTile(
                      client: displayed[index],
                      onOpen: () => _openClientFromSearch(displayed[index]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildAppointmentList() {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _appointmentSearchController,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            // Close the keyboard after the user submits a search.
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration:
                formInputDecoration(
                  context,
                  'Search by client or employee...',
                ).copyWith(
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  suffixIcon: _appointmentSearchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                          onPressed: () => setState(
                            () => _appointmentSearchController.clear(),
                          ),
                          tooltip: 'Clear',
                        )
                      : null,
                ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<AppointmentRecord>>(
            stream: _appointmentService.getAppointmentStatus('done'),
            // Takes all appointments with status done
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error : ${snapshot.error}'));
              }

              final appointments = snapshot.data ?? [];
              final query = _appointmentSearchController.text
                  .trim()
                  .toLowerCase();

              final filtered = query.isEmpty
                  ? appointments
                  : appointments.where((a) {
                      final matchesClient = a.clientName.toLowerCase().contains(
                        query,
                      );
                      final matchesEmployee = a.employeeNames.any(
                        (e) => e.toLowerCase().contains(query),
                      );
                      return matchesClient || matchesEmployee;
                    }).toList();

              final sorted = [...filtered]
                ..sort((a, b) => a.startTime.compareTo(b.startTime));

              if (sorted.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        query.isEmpty
                            ? Icons.event_busy_outlined
                            : Icons.search_off_outlined,
                        size: 40,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        query.isEmpty
                            ? 'No appointments found.'
                            : 'No appointments match "$query"',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => AppointmentTile(
                  appointment: sorted[index],
                  employees: _allEmployees,
                  showActions: false,
                  onOpen: () => _openAppointmentFromSearch(sorted[index]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
