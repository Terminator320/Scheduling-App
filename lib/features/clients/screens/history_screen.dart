import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/features/clients/widgets/views/appointment_history_view.dart';
import 'package:scheduling/features/settings/widgets/views/settings_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/fields/app_search_bar.dart';

/// Appointment history screen: a searchable, filterable list of past
/// (done/cancelled) appointments grouped by year and day. Owns only the
/// chrome — search field, nav shell, drawer — and delegates the list and its
/// year/employee filters to [AppointmentHistoryView].
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
    return Scaffold(
      appBar: AppTopBar(
        title: context.l10n.common_history,
        compact: context.isLandscape,
        onBack: _backToCalendar,
        bottom: AppSearchBar(
          controller: _searchController,
          hintText: context.l10n.clients_searchByClientOrEmployee,
        ),
      ),
      endDrawer: SettingsDrawer.endDrawerFor(
        context,
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
      body: ListenableBuilder(
        listenable: _searchController,
        builder: (context, _) => AdaptiveShell(
          currentDestination: AdaptiveDestination.history,
          isAdmin: widget.isAdmin,
          employeeId: widget.employeeId,
          child: AppointmentHistoryView(searchQuery: _searchController.text),
        ),
      ),
    );
  }
}
