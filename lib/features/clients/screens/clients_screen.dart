import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/calendar/services/appointment_service.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/clients/models/client_record.dart';
import 'package:scheduling/features/clients/services/client_service.dart';
import 'package:scheduling/features/clients/widgets/add_client_sheet.dart';
import 'package:scheduling/features/clients/widgets/client_detail_sheet.dart';
import 'package:scheduling/features/clients/widgets/client_tile.dart';
import 'package:scheduling/features/settings/widgets/settings_drawer.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/app_empty_state.dart';
import 'package:scheduling/shared/widgets/app_search_bar.dart';
import 'package:scheduling/shared/widgets/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/status_chip.dart';

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
  bool _clientsLoaded = false;
  List<ClientRecord> _allClients = [];
  final ClientService _clientService = ClientService();
  final AppointmentService _appointmentService = AppointmentService();
  StreamSubscription? _clientsSubscription;
  final UserService _userService = UserService();
  List<EmployeeRecord> _allEmployees = [];
  StreamSubscription? _employeesSubscription;


  bool get _isClients => widget.mode == 'Clients';

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  void _initStreams() {
    _clientsSubscription = _clientService.clientsStream().listen((clients) {
      if (mounted) {
        setState(() {
          _allClients = clients;
          _clientsLoaded = true;
        });
      }
    });
    _employeesSubscription = _userService.allUsersStream().listen((data) {
      if (mounted) setState(() => _allEmployees = data);
    });
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      setState(() => _displayLimit += 50);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
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

  PreferredSizeWidget _buildClientsAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.pushReplacementNamed(
          context,
          AppRoutes.mainCalendar,
          arguments: MainCalendarArgs(
            isAdmin: widget.isAdmin,
            employeeId: widget.employeeId,
          ),
        ),
      ),
      title: Text(
        context.l10n.clients,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
      ),
      bottom: AppSearchBar(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        hintText: context.l10n.searchByNameOrPhone,
      ),
    );
  }

  PreferredSizeWidget _buildHistoryAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.pushReplacementNamed(
          context,
          AppRoutes.mainCalendar,
          arguments: MainCalendarArgs(
            isAdmin: widget.isAdmin,
            employeeId: widget.employeeId,
          ),
        ),
      ),
      title: Text(
        context.l10n.history,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            controller: _appointmentSearchController,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: context.l10n.searchByClientOrEmployee,
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 16,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.r12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isClients ? _buildClientsAppBar() : _buildHistoryAppBar(),
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
    final query = _searchController.text.trim().toLowerCase();

    // Show skeleton while the first subscription data hasn't arrived yet
    if (!_clientsLoaded) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.sp16),
        children: const [
          SkeletonListTile(),
          SizedBox(height: 8),
          SkeletonListTile(),
          SizedBox(height: 8),
          SkeletonListTile(),
          SizedBox(height: 8),
          SkeletonListTile(),
        ],
      );
    }

    final filtered = query.isEmpty
        ? _allClients
        : _allClients.where((c) {
            return c.displayName.toLowerCase().contains(query) ||
                c.phone.contains(query);
          }).toList();

    final displayed = filtered.length > _displayLimit
        ? filtered.sublist(0, _displayLimit)
        : filtered;

    if (displayed.isEmpty) {
      return AppEmptyState(
        icon: query.isEmpty ? Icons.people_outline : Icons.search_off_outlined,
        title: query.isEmpty
            ? context.l10n.noClientsYet
            : '${context.l10n.noClientsMatch} "$query"',
        body: query.isEmpty
            ? context.l10n.tapToAddYourFirstClient
            : context.l10n.tryADifferentSearchTerm,
        actionLabel: query.isEmpty && widget.isAdmin
            ? context.l10n.addClient
            : null,
        onAction: query.isEmpty && widget.isAdmin ? _onAddClient : null,
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: displayed.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, indent: 64, endIndent: 0),
      itemBuilder: (context, index) => ClientTile(
        client: displayed[index],
        onOpen: () => _openClientFromSearch(displayed[index]),
      ),
    );
  }

  Widget _buildAppointmentList() {
    final colorMap = buildEmployeeColorMap(_allEmployees);
    final query = _appointmentSearchController.text.trim().toLowerCase();

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: StreamBuilder<List<AppointmentRecord>>(
        stream: _appointmentService.getHistoryAppointments(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              padding: const EdgeInsets.all(12),
              children: const [
                SkeletonListTile(),
                SizedBox(height: 8),
                SkeletonListTile(),
                SizedBox(height: 8),
                SkeletonListTile(),
              ],
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final appointments = snapshot.data ?? [];

          final filtered = query.isEmpty
              ? appointments
              : appointments.where((a) {
                  final matchesClient =
                      a.clientName.toLowerCase().contains(query);
                  final matchesEmployee =
                      a.employeeNames.any((e) => e.toLowerCase().contains(query));
                  return matchesClient || matchesEmployee;
                }).toList();

          if (filtered.isEmpty) {
            return AppEmptyState(
              icon: query.isEmpty
                  ? Icons.history_outlined
                  : Icons.search_off_outlined,
              title: query.isEmpty
                  ? context.l10n.noAppointmentsFound
                  : '${context.l10n.noAppointmentsMatch} "$query"',
              body: query.isEmpty
                  ? context.l10n.tapToScheduleAnAppointment
                  : context.l10n.tryADifferentSearchTerm,
            );
          }

          // Sort descending (newest first)
          filtered.sort((a, b) => b.startTime.compareTo(a.startTime));

          // Group by date
          final locale = Intl.defaultLocale ?? 'en_CA';
          final dateKeyFormat = DateFormat('yyyy-MM-dd');
          final dateHeaderFormat = DateFormat('EEEE, MMMM d', locale);

          final grouped = <String, List<AppointmentRecord>>{};
          for (final app in filtered) {
            final key = dateKeyFormat.format(app.startTime);
            grouped.putIfAbsent(key, () => []).add(app);
          }

          final sortedKeys = grouped.keys.toList()
            ..sort((a, b) => b.compareTo(a));

          // Build flat list of widgets
          final items = <Widget>[];
          for (final key in sortedKeys) {
            final group = grouped[key]!;
            final date = DateTime.parse(key);
            final label = dateHeaderFormat.format(date).toUpperCase();

            items.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            );

            for (int i = 0; i < group.length; i++) {
              items.add(
                _HistoryCard(
                  appointment: group[i],
                  employeeColorMap: colorMap,
                ),
              );
              if (i < group.length - 1) {
                items.add(const SizedBox(height: 7));
              }
            }
            items.add(const SizedBox(height: 8));
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: items,
          );
        },
      ),
    );
  }
}

AppointmentStatus _mapHistoryStatus(String status) =>
    switch (status.toLowerCase()) {
      'confirmed' => AppointmentStatus.confirmed,
      'done' || 'completed' => AppointmentStatus.done,
      'cancelled' => AppointmentStatus.cancelled,
      'in_progress' || 'inprogress' => AppointmentStatus.inProgress,
      _ => AppointmentStatus.pending,
    };

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.appointment,
    required this.employeeColorMap,
  });

  final AppointmentRecord appointment;
  final Map<String, Color> employeeColorMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCancelled = appointment.status.toLowerCase() == 'cancelled';
    final accent =
        colorFromMap(appointment, employeeColorMap) ?? AppColors.primary;
    final status = _mapHistoryStatus(appointment.displayStatus);

    final employeeName = appointment.employeeNames.isNotEmpty
        ? appointment.employeeNames.first
        : null;

    final timeLabel =
        '${DateUtilsHelper.formatTime(appointment.startTime)} – ${DateUtilsHelper.formatTime(appointment.endTime)}'
        '${employeeName != null ? ' · $employeeName' : ''}';

    Widget card = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showEventDetails(context, appointment, showActions: false),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        appointment.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          decoration: isCancelled
                              ? TextDecoration.lineThrough
                              : null,
                          color: isCancelled ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              timeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10, left: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(status: status),
                    const SizedBox(width: 7),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (isCancelled) {
      card = Opacity(opacity: 0.75, child: card);
    }

    return card;
  }
}
