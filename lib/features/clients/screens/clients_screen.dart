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
import 'package:scheduling/shared/widgets/fields/app_search_bar.dart';

class ListInformation extends StatefulWidget {
  const ListInformation({
    required this.mode,
    required this.isAdmin,
    required this.employeeId,
    super.key,
  });

  final String mode;
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

  bool get _isClients => widget.mode == 'Clients';

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
    if (context.isWide) {
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

  PreferredSizeWidget _buildClientsAppBar() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppBar(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
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
        context.l10n.common_clients,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      bottom: AppSearchBar(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        hintText: context.l10n.clients_searchByNameOrPhone,
      ),
    );
  }

  PreferredSizeWidget _buildHistoryAppBar() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppBar(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
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
        context.l10n.common_history,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            controller: _appointmentSearchController,
            onChanged: (_) => setState(() {}),

            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onPrimary,
            ),
            decoration: InputDecoration(
              hintText: context.l10n.clients_searchByClientOrEmployee,
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimary.withValues(alpha: 0.6),
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 16,
                color: scheme.onPrimary.withValues(alpha: 0.7),
              ),
              filled: true,
              fillColor: scheme.onPrimary.withValues(alpha: 0.15),
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
      body: AdaptiveShell(
        currentDestination: _isClients
            ? AdaptiveDestination.clients
            : AdaptiveDestination.history,
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
        child: body,
      ),
    );
  }
}
