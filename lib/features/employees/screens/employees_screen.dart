import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/core/utils/sheet_focus.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/widgets/employee_card.dart';
import 'package:scheduling/features/employees/widgets/employee_details_sheet.dart';
import 'package:scheduling/features/employees/widgets/employee_form_sheet.dart';
import 'package:scheduling/features/settings/widgets/settings_drawer.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/app_empty_state.dart';
import 'package:scheduling/shared/widgets/app_search_bar.dart';
import 'package:scheduling/shared/widgets/skeleton_loader.dart';

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
      builder: (_) =>
          EmployeeFormSheet(employee: employee, usedColors: usedColors),
    );

    if (!mounted) return;
    await SheetFocus.unfocusAfterSheet();

    final notices = ref.read(noticeServiceProvider);
    if (result == 'deleted') {
      notices.success(context.l10n.employeeDeleted);
    } else if (result == true) {
      notices.success(
        employee == null
            ? context.l10n.employeeAddedSuccessfully
            : context.l10n.employeeUpdatedSuccessfully,
      );
    }
  }

  Future<void> _showEmployeeDetails(EmployeeRecord employee) async {
    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EmployeeDetailsSheet(employee: employee),
    );

    if (!mounted) return;
    await SheetFocus.unfocusAfterSheet();

    if (result == 'edit') {
      await _openEmployeeSheet(employee: employee);
    } else if (result == 'deleted') {
      ref.read(noticeServiceProvider).success(context.l10n.employeeDeleted);
    }
  }

  void _clearSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_searchController.text.isEmpty) return;
    setState(_searchController.clear);
  }

  PreferredSizeWidget _buildAppBar() {
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
        context.l10n.employees,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
      ),
      bottom: AppSearchBar(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        hintText: context.l10n.searchEmployees,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(employeesStreamProvider);

    return Scaffold(
      appBar: _buildAppBar(),
      endDrawer: SettingsDrawer(
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
              onPressed: _openEmployeeSheet,
              child: const Icon(Icons.add),
            )
          : null,
      body: employeesAsync.when(
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
        error: (_, _) =>
            Center(child: Text(context.l10n.errorLoadingEmployees)),
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
                  ? context.l10n.noEmployeesYet
                  : context.l10n.noEmployeesFound,
              body: query.isEmpty
                  ? context.l10n.tapToInviteYourFirstEmployee
                  : context.l10n.tryADifferentSearchTerm,
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: filtered.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, indent: 64),
            itemBuilder: (context, index) {
              final employee = filtered[index];
              return EmployeeCard(
                employee: employee,
                onTap: () async {
                  _clearSearch();
                  await Future<void>.delayed(const Duration(milliseconds: 80));
                  if (!mounted) return;
                  await _showEmployeeDetails(employee);
                },
              );
            },
          );
        },
      ),
    );
  }
}
