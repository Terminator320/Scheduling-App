import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/master_detail_scaffold.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/navigation/hub_shell_scope.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/sheet_focus.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/widgets/cards/employee_card.dart';
import 'package:scheduling/features/employees/widgets/sheets/edit_person_sheet.dart';
import 'package:scheduling/features/employees/widgets/sheets/employee_details_sheet.dart';
import 'package:scheduling/features/employees/widgets/sheets/employee_form_sheet.dart';
import 'package:scheduling/features/employees/widgets/views/employee_details_view.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
import 'package:scheduling/features/feature_tour/widgets/tour_showcase.dart';
import 'package:scheduling/features/navigation/widgets/app_nav_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_header_pair.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/fields/app_search_bar.dart';
import 'package:scheduling/shared/widgets/primitives/fade_in_item.dart';
import 'package:scheduling/shared/widgets/sheets/app_bottom_sheet.dart';

class AddEmployeePage extends ConsumerStatefulWidget {
  const AddEmployeePage({
    required this.isAdmin,
    required this.employeeId,
    super.key,
  });

  final bool isAdmin;
  final String employeeId;

  @override
  ConsumerState<AddEmployeePage> createState() => _AddEmployeePageState();
}

class _AddEmployeePageState extends ConsumerState<AddEmployeePage> {
  final TextEditingController _searchController = TextEditingController();
  EmployeeRecord? _selectedEmployee;

  late final List<TourStepId> _tourSteps = tourStepsFor(
    HubTab.employees,
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
    destination: HubTab.employees,
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

  Set<int> _usedColors(List<EmployeeRecord> employees, {String? excludeId}) {
    return employees
        .where((e) => e.id != excludeId)
        .map((e) => e.color.toARGB32())
        .toSet();
  }

  Future<void> _openEmployeeSheet({EmployeeRecord? employee}) async {
    // Every status counts as taken, not just active ones: a DISABLED
    // employee's colour must stay reserved (re-enabling them would otherwise
    // collide with whoever took it, and the crew colour is what the appointment
    // bar and the calendar dots are keyed on), and an INVITED employee's colour
    // was already reserved by the invite. `employeesStreamProvider` filters to
    // active, so it is the wrong source here.
    final employees =
        ref.read(allUsersStreamProvider).asData?.value ?? const [];
    final usedColors = _usedColors(employees, excludeId: employee?.id);

    // The edit sheet announces its own success notice and returns the saved
    // record; the invite sheet still returns a bool.
    if (employee != null) {
      final saved = await showEditPersonSheet(
        context,
        employee,
        usedColors: usedColors,
      );
      if (!mounted) return;
      await SheetFocus.unfocusAfterSheet();
      if (!mounted) return;
      if (saved != null) setState(() => _selectedEmployee = saved);
      return;
    }

    final result = await showAppBottomSheet<Object?>(
      context,
      builder: (_) => EmployeeFormSheet(usedColors: usedColors),
    );

    if (!mounted) return;
    await SheetFocus.unfocusAfterSheet();
    if (!mounted) return;

    if (result == true) {
      ref
          .read(noticeServiceProvider)
          .success(context.l10n.employees_employeeAddedSuccessfully);
    }
  }

  Future<void> _onEmployeeTap(EmployeeRecord employee) async {
    _clearSearch();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    if (context.isTwoPane) {
      setState(() => _selectedEmployee = employee);
      return;
    }

    await _showEmployeeDetailsSheet(employee);
  }

  Future<void> _showEmployeeDetailsSheet(EmployeeRecord employee) async {
    final result = await showAppBottomSheet<Object?>(
      context,
      builder: (_) => EmployeeDetailsSheet(
        employee: employee,
        isCurrentUserAdmin: widget.isAdmin,
      ),
    );

    if (!mounted) return;
    await SheetFocus.unfocusAfterSheet();
    if (!mounted) return;
    // Edit is the only action the detail sheet can raise: disable/enable moved
    // into the edit sheet (which announces its own notice) and delete is gone.
    if (result == 'edit') await _openEmployeeSheet(employee: employee);
  }

  void _clearSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
  }

  PreferredSizeWidget _buildAppBar() {
    final searchBar = AppSearchBar(
      textScaler: MediaQuery.textScalerOf(context),
      controller: _searchController,
      hintText: context.l10n.employees_searchEmployees,
    );
    return AppTopBar(
      title: context.l10n.common_employees,
      compact: context.isLandscape,
      onBack: () => navigateToDestination(
        context,
        HubTab.calendar,
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
      actions: const [AppHeaderPair()],
      bottom: _tourSteps.contains(TourStepId.employeesSearch)
          ? TourShowcaseBar(
              showcaseKey: _tourKeys[TourStepId.employeesSearch]!,
              destination: HubTab.employees,
              id: TourStepId.employeesSearch,
              index: _tourSteps.indexOf(TourStepId.employeesSearch),
              count: _tourSteps.length,
              bar: searchBar,
            )
          : searchBar,
    );
  }

  Widget _buildMasterList() {
    final employeesAsync = ref.watch(employeesStreamProvider);
    return employeesAsync.when(
      loading: () => ListView(
        padding: const EdgeInsets.all(AppSpacing.sp16),
        children: const [
          SkeletonListTile(),
          SizedBox(height: AppSpacing.sp12),
          SkeletonListTile(),
          SizedBox(height: AppSpacing.sp12),
          SkeletonListTile(),
        ],
      ),
      error: (_, _) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.error_errorLoadingEmployees),
              const SizedBox(height: AppSpacing.sp16),
              TextButton.icon(
                onPressed: () => ref.invalidate(employeesStreamProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.l10n.common_retry),
              ),
            ],
          ),
        );
      },
      data: (_) {
        final filtered = ref.watch(
          filteredEmployeesProvider(_searchController.text),
        );

        if (filtered.isEmpty) {
          final query = _searchController.text.trim();
          return AppEmptyState(
            icon: query.isEmpty
                ? Icons.badge_outlined
                : Icons.search_off_outlined,
            title: query.isEmpty
                ? context.l10n.employees_noEmployeesYet
                : context.l10n.common_noEmployeesFound,
            body: query.isEmpty
                ? context.l10n.employees_tapToInviteYourFirstEmployee
                : context.l10n.common_tryADifferentSearchTerm,
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: AppSpacing.sp16),
          itemCount: filtered.length,
          separatorBuilder: (context, index) =>
              const Divider(height: 1, indent: 64),
          itemBuilder: (context, index) {
            final employee = filtered[index];
            return FadeInItem(
              key: ValueKey(employee.id),
              index: index,
              child: EmployeeCard(
                employee: employee,
                // Only highlight when the detail pane is actually shown (two-pane).
                selected:
                    context.isTwoPane && _selectedEmployee?.id == employee.id,
                onTap: () => _onEmployeeTap(employee),
              ),
            );
          },
        );
      },
    );
  }

  /// Keeps the selected employee in sync with the live users stream, so an in-pane
  /// enable/disable/edit doesn't leave the detail pane showing a stale status.
  EmployeeRecord? _liveSelectedEmployee() {
    final snapshot = _selectedEmployee;
    if (snapshot == null) return null;
    final liveUsers = ref.watch(allUsersStreamProvider).asData?.value;
    if (liveUsers == null) return snapshot;
    for (final employee in liveUsers) {
      if (employee.id == snapshot.id) return employee;
    }
    return null;
  }

  Widget _buildDetailPlaceholder() => DetailPlaceholder(
    icon: Icons.badge_outlined,
    message: context.l10n.employees_selectAnEmployeeToViewDetails,
  );

  @override
  Widget build(BuildContext context) {
    // Only log on the data→error transition — otherwise this would re-log on every rebuild while the stream stays errored.
    ref.listen(employeesStreamProvider, (previous, next) {
      if (next is! AsyncError || previous is AsyncError) return;
      ref
          .read(loggerProvider)
          .warn('employeesStreamProvider error', next.error, next.stackTrace);
    });
    final selected = _liveSelectedEmployee();
    return FeatureTourHost(
      destination: HubTab.employees,
      isAdmin: widget.isAdmin,
      stepKeys: _tourKeys,
      child: Scaffold(
        appBar: _buildAppBar(),
        endDrawer: AppNavDrawer(
          isAdmin: widget.isAdmin,
          employeeId: widget.employeeId,
        ),
        floatingActionButton: widget.isAdmin
            ? _tourStep(
                TourStepId.employeesAdd,
                targetBorderRadius: BorderRadius.circular(AppRadius.r16),
                child: FloatingActionButton(
                  // Needs to be unique across tabs, since IndexedStack keeps every tab's FAB mounted at the same time.
                  heroTag: 'employeesAddFab',
                  onPressed: _openEmployeeSheet,
                  tooltip: context.l10n.employees_inviteEmployee,
                  child: const Icon(Icons.add),
                ),
              )
            : null,
        // Only the master list listens to the search controller, so typing rebuilds just the list.
        body: MasterDetailScaffold(
          master: ListenableBuilder(
            listenable: _searchController,
            builder: (context, _) => _buildMasterList(),
          ),
          detail: selected == null
              ? null
              : EmployeeDetailsView(
                  key: ValueKey(selected.id),
                  employee: selected,
                  isCurrentUserAdmin: widget.isAdmin,
                  onEdit: () => _openEmployeeSheet(employee: selected),
                ),
          placeholder: _buildDetailPlaceholder(),
        ),
      ),
    );
  }
}
