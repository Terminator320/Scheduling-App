import 'package:flutter/material.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/master_detail_scaffold.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/sheet_focus.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/sheets/add_client_sheet.dart';
import 'package:scheduling/features/clients/widgets/sheets/client_detail_sheet.dart';
import 'package:scheduling/features/clients/widgets/views/appointment_history_view.dart';
import 'package:scheduling/features/clients/widgets/views/client_detail_view.dart';
import 'package:scheduling/features/clients/widgets/views/clients_list_view.dart';
import 'package:scheduling/features/settings/widgets/views/settings_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/fields/app_search_bar.dart';

class ListInformation extends StatefulWidget {
  const ListInformation({
    required this.mode,
    required this.isAdmin,
    required this.employeeId,
    super.key,
  });

  final ClientsMode mode;
  final bool isAdmin;
  final String employeeId;

  @override
  State<ListInformation> createState() => _ListInformationState();
}

class _ListInformationState extends State<ListInformation> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _appointmentSearchController =
      TextEditingController();
  ClientRecord? _selectedClient;

  bool get _isClients => widget.mode == ClientsMode.clients;

  @override
  void dispose() {
    _searchController.dispose();
    _appointmentSearchController.dispose();
    super.dispose();
  }

  Future<void> _onAddClient() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: AppMotion.sheetStyle,
      builder: (_) => const AddClientSheet(),
    );
  }

  Future<void> _onClientTap(ClientRecord client) async {
    if (context.isSplitLayout) {
      setState(() => _selectedClient = client);
      return;
    }

    await SheetFocus.settleBeforeSheet();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: AppMotion.sheetStyle,
      builder: (_) => ClientDetailSheet(client: client),
    );

    if (!mounted) return;
    await SheetFocus.unfocusAfterSheet();
  }

  void _backToCalendar() => Navigator.pushReplacementNamed(
    context,
    AppRoutes.mainCalendar,
    arguments: MainCalendarArgs(
      isAdmin: widget.isAdmin,
      employeeId: widget.employeeId,
    ),
  );

  PreferredSizeWidget _buildClientsAppBar() {
    return AppTopBar(
      title: context.l10n.common_clients,
      compact: context.isLandscape,
      onBack: _backToCalendar,
      bottom: AppSearchBar(
        controller: _searchController,
        hintText: context.l10n.clients_searchByNameOrPhone,
      ),
    );
  }

  PreferredSizeWidget _buildHistoryAppBar() {
    return AppTopBar(
      title: context.l10n.common_history,
      compact: context.isLandscape,
      onBack: _backToCalendar,
      bottom: AppSearchBar(
        controller: _appointmentSearchController,
        hintText: context.l10n.clients_searchByClientOrEmployee,
      ),
    );
  }

  Widget _buildMaster() {
    if (!_isClients) {
      return AppointmentHistoryView(
        searchQuery: _appointmentSearchController.text,
      );
    }
    return ClientsListView(
      searchQuery: _searchController.text,
      isAdmin: widget.isAdmin,
      selectedClientId: _selectedClient?.id,
      onClientTap: _onClientTap,
    );
  }

  Widget _buildDetailPlaceholder() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sp24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              _isClients
                  ? context.l10n.clients_selectAClientToViewDetails
                  : context.l10n.clients_noClientsYet,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isClients ? _buildClientsAppBar() : _buildHistoryAppBar(),
      endDrawer: SettingsDrawer.endDrawerFor(
        context,
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
      floatingActionButton: widget.isAdmin && _isClients
          ? FloatingActionButton(
              onPressed: _onAddClient,
              child: const Icon(Icons.add),
            )
          : null,
      body: ListenableBuilder(
        listenable: Listenable.merge([
          _searchController,
          _appointmentSearchController,
        ]),
        builder: (context, _) {
          final body = MasterDetailScaffold(
            master: _buildMaster(),
            detail: _isClients && _selectedClient != null
                ? ClientDetailView(
                    key: ValueKey(_selectedClient!.id),
                    client: _selectedClient!,
                  )
                : null,
            placeholder: _buildDetailPlaceholder(),
          );
          return AdaptiveShell(
            currentDestination: _isClients
                ? AdaptiveDestination.clients
                : AdaptiveDestination.history,
            isAdmin: widget.isAdmin,
            employeeId: widget.employeeId,
            child: body,
          );
        },
      ),
    );
  }
}
