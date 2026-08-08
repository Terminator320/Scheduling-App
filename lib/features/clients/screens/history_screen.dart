import 'package:flutter/material.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/primary_scroll_scope.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/features/clients/widgets/views/appointment_history_view.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/domain/tour_steps.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
import 'package:scheduling/features/navigation/widgets/app_nav_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_header_pair.dart';
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

  /// Whether the list's first page has settled — gates the feature tour.
  bool _listSettled = false;

  late final _tour = TourSteps(
    const DestinationTour(PushedDestination.history),
    isAdmin: widget.isAdmin,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onListSettled() {
    if (_listSettled) return;
    setState(() => _listSettled = true);
  }

  // A pushed route now, so back means back. The Calendar pill covers
  // go-home.
  void _back() => Navigator.maybePop(context);

  @override
  Widget build(BuildContext context) {
    final searchBar = AppSearchBar(
      textScaler: MediaQuery.textScalerOf(context),
      controller: _searchController,
      hintText: context.l10n.clients_searchByClientOrEmployee,
    );
    return FeatureTourHost(
      scope: _tour.scope,
      isAdmin: widget.isAdmin,
      stepKeys: _tour.keys,
      // The filter bar only renders once a page has supplied years/employees,
      // and the first row doesn't exist before then. A tour started against
      // the skeleton finds only the search bar, drops the other two steps and
      // marks the WHOLE scope seen.
      ready: _listSettled,
      child: Scaffold(
        appBar: AppTopBar(
          title: context.l10n.common_history,
          compact: context.isLandscape,
          onBack: _back,
          actions: const [AppHeaderPair()],
          bottom: _tour.stepBarIf(TourStepId.historySearch, searchBar),
        ),
        endDrawer: AppNavDrawer(
          isAdmin: widget.isAdmin,
          employeeId: widget.employeeId,
        ),
        // The nav shell is built once; only the history view rebuilds per
        // keystroke, so typing doesn't rebuild the NavigationRail + chrome.
        body: PrimaryScrollScope(
          child: ListenableBuilder(
            listenable: _searchController,
            builder: (context, _) => AppointmentHistoryView(
              searchQuery: _searchController.text,
              filterTourWrap: (child) =>
                  _tour.stepIf(TourStepId.historyFilter, child),
              firstRowTourWrap: (child) =>
                  _tour.stepIf(TourStepId.historyRow, child),
              onFirstPageSettled: _onListSettled,
            ),
          ),
        ),
      ),
    );
  }
}
