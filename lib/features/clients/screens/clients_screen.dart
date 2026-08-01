import 'package:flutter/material.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/master_detail_scaffold.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/navigation/hub_shell_scope.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/sections/client_tag_filter_bar.dart';
import 'package:scheduling/features/clients/widgets/sheets/add_client_sheet.dart';
import 'package:scheduling/features/clients/widgets/sheets/client_detail_sheet.dart';
import 'package:scheduling/features/clients/widgets/views/client_detail_view.dart';
import 'package:scheduling/features/clients/widgets/views/clients_list_view.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
import 'package:scheduling/features/feature_tour/widgets/tour_showcase.dart';
import 'package:scheduling/features/navigation/widgets/app_nav_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_header_pair.dart';
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
  String? _selectedTag;

  late final List<TourStepId> _tourSteps = tourStepsFor(
    HubTab.clients,
    isAdmin: widget.isAdmin,
  );
  late final Map<TourStepId, GlobalKey> _tourKeys = {
    for (final id in _tourSteps) id: GlobalKey(),
  };

  Widget _tourStep(
    TourStepId id, {
    required Widget child,
    BorderRadius? targetBorderRadius,
  }) => TourShowcase(
    showcaseKey: _tourKeys[id]!,
    destination: HubTab.clients,
    id: id,
    index: _tourSteps.indexOf(id),
    count: _tourSteps.length,
    targetBorderRadius: targetBorderRadius,
    child: child,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onAddClient() async {
    final result = await showAddClientSheet(context);
    if (result == null || result.next != AddClientNext.bookJob) return;
    if (!mounted) return;
    // Sequential, never stacked — the add-client sheet has already popped.
    await showAddEventPopup(context, initialClient: result.client);
  }

  Future<void> _onClientTap(ClientRecord client) async {
    if (context.isTwoPane) {
      setState(() => _selectedClient = client);
      return;
    }

    await showClientDetailSheet(context, client);
  }

  void _backToCalendar() => navigateToDestination(
    context,
    HubTab.calendar,
    isAdmin: widget.isAdmin,
    employeeId: widget.employeeId,
  );

  Widget _buildDetailPlaceholder() => DetailPlaceholder(
    icon: Icons.people_outline_rounded,
    message: context.l10n.clients_selectAClientToViewDetails,
  );

  @override
  Widget build(BuildContext context) {
    final searchBar = AppSearchBar(
      textScaler: MediaQuery.textScalerOf(context),
      controller: _searchController,
      hintText: context.l10n.clients_searchByNameOrPhone,
    );
    return FeatureTourHost(
      destination: HubTab.clients,
      isAdmin: widget.isAdmin,
      stepKeys: _tourKeys,
      child: Scaffold(
        appBar: AppTopBar(
          title: context.l10n.common_clients,
          compact: context.isLandscape,
          onBack: _backToCalendar,
          actions: const [AppHeaderPair()],
          bottom: _tourSteps.contains(TourStepId.clientsSearch)
              ? TourShowcaseBar(
                  showcaseKey: _tourKeys[TourStepId.clientsSearch]!,
                  destination: HubTab.clients,
                  id: TourStepId.clientsSearch,
                  index: _tourSteps.indexOf(TourStepId.clientsSearch),
                  count: _tourSteps.length,
                  bar: searchBar,
                )
              : searchBar,
        ),
        endDrawer: AppNavDrawer(
          isAdmin: widget.isAdmin,
          employeeId: widget.employeeId,
        ),
        floatingActionButton: widget.isAdmin
            ? _tourStep(
                TourStepId.clientsAdd,
                targetBorderRadius: BorderRadius.circular(AppRadius.r16),
                child: FloatingActionButton(
                  // Needs to be unique across tabs, since IndexedStack keeps every tab's FAB mounted at the same time.
                  heroTag: 'clientsAddFab',
                  onPressed: _onAddClient,
                  tooltip: context.l10n.clients_addClient,
                  child: const Icon(Icons.add),
                ),
              )
            : null,
        // Only the master list listens to the search controller, so typing rebuilds just the list.
        body: MasterDetailScaffold(
          master: Column(
            children: [
              ClientTagFilterBar(
                selected: _selectedTag,
                onChanged: (next) => setState(() => _selectedTag = next),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _searchController,
                  builder: (context, _) => ClientsListView(
                    searchQuery: _searchController.text,
                    isAdmin: widget.isAdmin,
                    selectedTag: _selectedTag,
                    // Only highlight the selected row when the detail pane is shown (two-pane).
                    selectedClientId: context.isTwoPane
                        ? _selectedClient?.id
                        : null,
                    onClientTap: _onClientTap,
                  ),
                ),
              ),
            ],
          ),
          detail: _selectedClient != null
              ? ClientDetailView(
                  key: ValueKey(_selectedClient!.id),
                  client: _selectedClient!,
                )
              : null,
          placeholder: _buildDetailPlaceholder(),
        ),
      ),
    );
  }
}
