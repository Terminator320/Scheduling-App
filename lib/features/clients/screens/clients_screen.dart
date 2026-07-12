import 'package:flutter/material.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/master_detail_scaffold.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/sheet_focus.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/sheets/add_client_sheet.dart';
import 'package:scheduling/features/clients/widgets/sheets/client_detail_sheet.dart';
import 'package:scheduling/features/clients/widgets/views/client_detail_view.dart';
import 'package:scheduling/features/clients/widgets/views/clients_list_view.dart';
import 'package:scheduling/features/settings/widgets/views/settings_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';
import 'package:scheduling/shared/widgets/fields/app_search_bar.dart';

class ListInformation extends StatefulWidget {
  const ListInformation({
    required this.isAdmin,
    required this.employeeId,
    super.key,
  });

  final bool isAdmin;
  final String employeeId;

  @override
  State<ListInformation> createState() => _ListInformationState();
}

class _ListInformationState extends State<ListInformation> {
  final TextEditingController _searchController = TextEditingController();
  ClientRecord? _selectedClient;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onAddClient() async {
    await showAddClientSheet(context);
  }

  Future<void> _onClientTap(ClientRecord client) async {
    if (context.isTwoPane) {
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

  void _backToCalendar() => navigateToDestination(
    context,
    AdaptiveDestination.calendar,
    isAdmin: widget.isAdmin,
    employeeId: widget.employeeId,
  );

  Widget _buildDetailPlaceholder() => DetailPlaceholder(
    icon: Icons.people_outline_rounded,
    message: context.l10n.clients_selectAClientToViewDetails,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: context.l10n.common_clients,
        compact: context.isLandscape,
        onBack: _backToCalendar,
        bottom: AppSearchBar(
          textScaler: MediaQuery.textScalerOf(context),
          controller: _searchController,
          hintText: context.l10n.clients_searchByNameOrPhone,
        ),
      ),
      endDrawer: SettingsDrawer.endDrawerFor(
        context,
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
              // Unique across the hub: the IndexedStack keeps every tab's
              // Scaffold (and FAB) mounted at once, so a default/shared hero
              // tag collides with another tab's FAB ("multiple heroes share
              // the same tag").
              heroTag: 'clientsAddFab',
              onPressed: _onAddClient,
              tooltip: context.l10n.clients_addClient,
              child: const Icon(Icons.add),
            )
          : null,
      // The nav shell is built once. Only the master list listens to the search
      // controller, so typing rebuilds just the list — not the chrome, and not
      // the (search-independent) detail pane in the split layout.
      body: AdaptiveShell(
        currentDestination: AdaptiveDestination.clients,
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
        child: MasterDetailScaffold(
          master: ListenableBuilder(
            listenable: _searchController,
            builder: (context, _) => ClientsListView(
              searchQuery: _searchController.text,
              isAdmin: widget.isAdmin,
              // Only highlight the selected row when the detail pane is
              // actually shown (two-pane). On a single-pane phone a tap opens a
              // sheet instead, so there is no persistent selection to reflect.
              selectedClientId: context.isTwoPane ? _selectedClient?.id : null,
              onClientTap: _onClientTap,
            ),
          ),
          detail: _selectedClient != null
              ? ClientDetailView(
                  key: ValueKey(_selectedClient!.id),
                  client: _selectedClient!,
                  onDeleted: () => setState(() => _selectedClient = null),
                )
              : null,
          placeholder: _buildDetailPlaceholder(),
        ),
      ),
    );
  }
}
