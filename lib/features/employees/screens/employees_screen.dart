import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/master_detail_scaffold.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/sheet_focus.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/widgets/cards/employee_card.dart';
import 'package:scheduling/features/employees/widgets/sheets/employee_details_sheet.dart';
import 'package:scheduling/features/employees/widgets/sheets/employee_form_sheet.dart';
import 'package:scheduling/features/employees/widgets/views/employee_details_view.dart';
import 'package:scheduling/features/settings/widgets/views/settings_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/fields/app_search_bar.dart';
import 'package:scheduling/shared/widgets/primitives/fade_in_item.dart';

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
    final employees =
        ref.read(employeesStreamProvider).asData?.value ?? const [];
    final usedColors = _usedColors(employees, excludeId: employee?.id);

    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: AppMotion.sheetStyle,
      builder: (_) =>
          EmployeeFormSheet(employee: employee, usedColors: usedColors),
    );

    if (!mounted) return;
    await SheetFocus.unfocusAfterSheet();
    if (!mounted) return;

    final notices = ref.read(noticeServiceProvider);
    if (result == 'deleted') {
      notices.success(context.l10n.employees_employeeDeleted);
    } else if (result == true) {
      notices.success(
        employee == null
            ? context.l10n.employees_employeeAddedSuccessfully
            : context.l10n.employees_employeeUpdatedSuccessfully,
      );
    }
  }

  Future<void> _onEmployeeTap(EmployeeRecord employee) async {
    _clearSearch();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    if (context.isSplitLayout) {
      setState(() => _selectedEmployee = employee);
      return;
    }

    await _showEmployeeDetailsSheet(employee);
  }

  Future<void> _showEmployeeDetailsSheet(EmployeeRecord employee) async {
    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: AppMotion.sheetStyle,
      builder: (_) => EmployeeDetailsSheet(
        employee: employee,
        isCurrentUserAdmin: widget.isAdmin,
      ),
    );

    if (!mounted) return;
    await SheetFocus.unfocusAfterSheet();
    if (result is String) _handleEmployeeAction(result, employee);
  }

  void _clearSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_searchController.text.isEmpty) return;
    setState(_searchController.clear);
  }

  PreferredSizeWidget _buildAppBar() {
    return AppTopBar(
      title: context.l10n.common_employees,
      compact: context.isLandscape,
      onBack: () => navigateToDestination(
        context,
        AdaptiveDestination.calendar,
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
      bottom: AppSearchBar(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        hintText: context.l10n.employees_searchEmployees,
      ),
    );
  }

  Widget _buildMasterList() {
    final employeesAsync = ref.watch(employeesStreamProvider);
    return employeesAsync.when(
      loading: () => ListView(
        padding: const EdgeInsets.all(AppSpacing.sp16),
        children: const [
          SkeletonListTile(),
          SizedBox(height: 12),
          SkeletonListTile(),
          SizedBox(height: 12),
          SkeletonListTile(),
        ],
      ),
      error: (err, stack) {
        ref
            .read(loggerProvider)
            .warn('employeesStreamProvider error', err, stack);
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
          padding: const EdgeInsets.only(bottom: 16),
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
                selected: _selectedEmployee?.id == employee.id,
                onTap: () => _onEmployeeTap(employee),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailPlaceholder() => DetailPlaceholder(
    icon: Icons.badge_outlined,
    message: context.l10n.employees_selectAnEmployeeToViewDetails,
  );

  void _handleEmployeeAction(String action, EmployeeRecord employee) {
    final notices = ref.read(noticeServiceProvider);
    switch (action) {
      case 'edit':
        _openEmployeeSheet(employee: employee);
      case 'deleted':
        setState(() => _selectedEmployee = null);
        notices.success(context.l10n.employees_employeeDeleted);
      case 'disabled':
        notices.success(context.l10n.employees_employeeDisabledSuccessfully);
      case 'enabled':
        notices.success(context.l10n.employees_employeeEnabledSuccessfully);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedEmployee;
    final body = MasterDetailScaffold(
      master: _buildMasterList(),
      detail: selected == null
          ? null
          : EmployeeDetailsView(
              key: ValueKey(selected.id),
              employee: selected,
              isCurrentUserAdmin: widget.isAdmin,
              onAction: (action) => _handleEmployeeAction(action, selected),
            ),
      placeholder: _buildDetailPlaceholder(),
    );

    return Scaffold(
      appBar: _buildAppBar(),
      endDrawer: SettingsDrawer.endDrawerFor(
        context,
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
              onPressed: _openEmployeeSheet,
              child: const Icon(Icons.add),
            )
          : null,
      body: AdaptiveShell(
        currentDestination: AdaptiveDestination.employees,
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
        child: body,
      ),
    );
  }
}
