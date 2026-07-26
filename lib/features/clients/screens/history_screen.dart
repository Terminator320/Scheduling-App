import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/features/clients/widgets/views/appointment_history_view.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
import 'package:scheduling/features/feature_tour/widgets/tour_showcase.dart';
import 'package:scheduling/features/settings/widgets/views/settings_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/fields/app_search_bar.dart';

/// The appointment history screen — searchable, filterable list. This owns the chrome
/// and delegates the actual list to AppointmentHistoryView.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    required this.isAdmin,
    required this.employeeId,
    super.key,
  });

  final bool isAdmin;
  final String employeeId;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  late final List<TourStepId> _tourSteps = tourStepsFor(
    AdaptiveDestination.history,
    isAdmin: widget.isAdmin,
  );
  late final Map<TourStepId, GlobalKey> _tourKeys = {
    for (final id in _tourSteps) id: GlobalKey(),
  };

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _backToCalendar() => navigateToDestination(
    context,
    AdaptiveDestination.calendar,
    isAdmin: widget.isAdmin,
    employeeId: widget.employeeId,
  );

  @override
  Widget build(BuildContext context) {
    final searchBar = AppSearchBar(
      textScaler: MediaQuery.textScalerOf(context),
      controller: _searchController,
      hintText: context.l10n.clients_searchByClientOrEmployee,
    );
    return FeatureTourHost(
      tab: AdaptiveDestination.history,
      isAdmin: widget.isAdmin,
      stepKeys: _tourKeys,
      child: Scaffold(
        appBar: AppTopBar(
          title: context.l10n.common_history,
          compact: context.isLandscape,
          onBack: _backToCalendar,
          bottom: _tourSteps.contains(TourStepId.historySearch)
              ? TourShowcaseBar(
                  showcaseKey: _tourKeys[TourStepId.historySearch]!,
                  tab: AdaptiveDestination.history,
                  id: TourStepId.historySearch,
                  index: _tourSteps.indexOf(TourStepId.historySearch),
                  count: _tourSteps.length,
                  bar: searchBar,
                )
              : searchBar,
        ),
        endDrawer: SettingsDrawer.endDrawerFor(
          context,
          isAdmin: widget.isAdmin,
          employeeId: widget.employeeId,
        ),
        // The nav shell is built once; only the history view rebuilds per
        // keystroke, so typing doesn't rebuild the NavigationRail + chrome.
        body: AdaptiveShell(
          currentDestination: AdaptiveDestination.history,
          isAdmin: widget.isAdmin,
          employeeId: widget.employeeId,
          child: ListenableBuilder(
            listenable: _searchController,
            builder: (context, _) =>
                AppointmentHistoryView(searchQuery: _searchController.text),
          ),
        ),
      ),
    );
  }
}
