import 'dart:async';

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
import 'package:scheduling/shared/widgets/app_search_bar.dart';
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
  List<EmployeeRecord> _employees = [];
  StreamSubscription<List<EmployeeRecord>>? _employeesSub;

  @override
  void initState() {
    super.initState();
    _employeesSub = _userService.employeesStream().listen((list) {
      if (mounted) setState(() => _employees = list);
    });
  }

  @override
  void dispose() {
    _employeesSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Set<int> _usedColors({String? excludeId}) {
    return _employees
        .where((e) => e.id != excludeId)
        .map((e) => e.color.toARGB32())
        .toSet();
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
    final usedColors = _usedColors(excludeId: employee?.id);
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EmployeeFormSheet(employee: employee, usedColors: usedColors),
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
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();

    if (result == 'edit') {
      await _openEmployeeSheet(employee: employee);
    } else if (result == 'deleted') {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.employeeDeleted)));
    }
  }

  void _clearSearch() {
    // Cancel search before opening a result so the list returns cleanly.
    FocusManager.instance.primaryFocus?.unfocus();
    if (_searchController.text.isEmpty) return;
    setState(() => _searchController.clear());
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
      bottom: AppSearchBar(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        hintText: context.l10n.searchEmployees,
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
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
              onPressed: _openEmployeeSheet,
              child: const Icon(Icons.add),
            )
          : null,
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
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: employees.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, indent: 64, endIndent: 0),
            itemBuilder: (context, index) {
              final employee = employees[index];
              return EmployeeCard(
                employee: employee,
                onTap: () async {
                  _clearSearch();
                  await Future<void>.delayed(const Duration(milliseconds: 80));
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
