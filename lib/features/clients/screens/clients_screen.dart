import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/clients/widgets/add_client_sheet.dart';
import 'package:scheduling/features/clients/widgets/appointment_history_view.dart';
import 'package:scheduling/features/clients/widgets/clients_list_view.dart';
import 'package:scheduling/features/settings/widgets/settings_drawer.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/app_search_bar.dart';

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
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 280),
        reverseDuration: Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
      builder: (_) => const AddClientSheet(),
    );
  }

  PreferredSizeWidget _buildClientsAppBar() {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
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
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
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
            style: TextStyle(color: scheme.onPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: context.l10n.searchByClientOrEmployee,
              hintStyle: TextStyle(
                color: scheme.onPrimary.withValues(alpha: 0.6),
                fontSize: 13,
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
      body: _isClients
          ? ClientsListView(
              searchQuery: _searchController.text,
              isAdmin: widget.isAdmin,
            )
          : AppointmentHistoryView(
              searchQuery: _appointmentSearchController.text,
            ),
    );
  }
}
