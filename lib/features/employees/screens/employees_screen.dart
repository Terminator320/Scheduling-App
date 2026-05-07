import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/features/employees/services/user_service.dart';
import 'package:scheduling/features/employees/widgets/employee_card.dart';
import 'package:scheduling/features/employees/widgets/employee_details_sheet.dart';
import 'package:scheduling/features/employees/widgets/employee_form_sheet.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/app_empty_state.dart';
import 'package:scheduling/shared/widgets/skeleton_loader.dart';

import 'package:scheduling/features/settings/widgets/settings_drawer.dart';

class AddEmployeePage extends StatefulWidget {
  final bool isAdmin;
  final String employeeId;

  const AddEmployeePage({
    super.key,
    required this.isAdmin,
    required this.employeeId,
  });

  @override
  State<AddEmployeePage> createState() => _AddEmployeePageState();
}

class _AddEmployeePageState extends State<AddEmployeePage> {
  final UserService _userService = UserService();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // methods
  List<EmployeeRecord> _filterEmployees(List<EmployeeRecord> employees) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return employees;

    return employees.where((e) {
      return e.name.toLowerCase().contains(query) ||
          e.email.toLowerCase().contains(query) ||
          e.phone.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openEmployeeSheet({EmployeeRecord? employee}) async {
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EmployeeFormSheet(employee: employee),
    );

    if (!mounted) return;
    // Keep search from regaining focus after the edit sheet closes.
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();

    if (result == 'deleted') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.employeeDeleted)));
    } else if (result == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            employee == null
                ? context.l10n.employeeAddedSuccessfully
                : context.l10n.employeeUpdatedSuccessfully,
          ),
        ),
      );
    }
  }

  Future<void> _showEmployeeDetails(EmployeeRecord employee) async {
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EmployeeDetailsSheet(employee: employee),
    );

    if (!mounted) return;
    // Keep search from regaining focus after the details sheet closes.
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (result != 'deleted') return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.employeeDeleted)));
  }

  void _clearSearch() {
    // Cancel search before opening a result so the list returns cleanly.
    FocusManager.instance.primaryFocus?.unfocus();
    if (_searchController.text.isEmpty) return;
    setState(() => _searchController.clear());
  }

  Future<void> _confirmDelete(EmployeeRecord employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.deleteEmployee),
        content: Text(
          ctx.l10n.areYouSureYouWantToDeleteThisEmployee,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _userService.deleteEmployee(employee.id);
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.employeeDeleted)));
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
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
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: context.l10n.searchEmployees,
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 16,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.15),
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
      appBar: _buildAppBar(),
      endDrawer: SettingsDrawer(
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openEmployeeSheet,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<EmployeeRecord>>(
        stream: _userService.employeesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.sp16),
              children: const [
                SkeletonListTile(),
                SizedBox(height: 12),
                SkeletonListTile(),
                SizedBox(height: 12),
                SkeletonListTile(),
              ],
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text(context.l10n.errorLoadingEmployees));
          }

          final employees = _filterEmployees(snapshot.data ?? []);

          if (employees.isEmpty) {
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: employees.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final employee = employees[index];
              return EmployeeCard(
                employee: employee,
                onTap: () async {
                  _clearSearch();
                  await Future<void>.delayed(const Duration(milliseconds: 80));
                  await _showEmployeeDetails(employee);
                },
                onEdit: () async {
                  _clearSearch();
                  await Future<void>.delayed(const Duration(milliseconds: 80));
                  await _openEmployeeSheet(employee: employee);
                },
                onDelete: () => _confirmDelete(employee),
              );
            },
          );
        },
      ),
    );
  }
}
