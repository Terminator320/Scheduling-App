import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/features/employees/services/user_service.dart';
import 'package:scheduling/features/employees/widgets/employee_card.dart';
import 'package:scheduling/features/employees/widgets/employee_details_sheet.dart';
import 'package:scheduling/features/employees/widgets/employee_form_sheet.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';

import 'package:scheduling/features/settings/widgets/settings_drawer.dart';

import '../../../shared/widgets/appScaffoldBar.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appScaffoldBar(
        context,
        context.l10n.employees,
        widget.employeeId,
        widget.isAdmin,
      ),
      endDrawer: SettingsDrawer(
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openEmployeeSheet,
        child: const Icon(FontAwesomeIcons.plus),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            children: [
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                // Close the keyboard after the user submits a search.
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                decoration: formInputDecoration(
                  context,
                  context.l10n.searchByNameOrPhoneNumber2,
                ).copyWith(prefixIcon: const Icon(FontAwesomeIcons.magnifyingGlass, size: 18)),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: StreamBuilder<List<EmployeeRecord>>(
                  stream: _userService.employeesStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(context.l10n.errorLoadingEmployees),
                      );
                    }

                    final employees = _filterEmployees(snapshot.data ?? []);
                    if (employees.isEmpty) {
                      return Center(
                        child: Text(context.l10n.noEmployeesFound),
                      );
                    }

                    return ListView.separated(
                      itemCount: employees.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final employee = employees[index];
                        return EmployeeCard(
                          employee: employee,
                          onTap: () async {
                            _clearSearch();
                            // Let the search clear/unfocus before pushing the sheet.
                            await Future<void>.delayed(
                              const Duration(milliseconds: 80),
                            );
                            await _showEmployeeDetails(employee);
                          },
                          onEdit: () async {
                            _clearSearch();
                            // Let the search clear/unfocus before pushing the sheet.
                            await Future<void>.delayed(
                              const Duration(milliseconds: 80),
                            );
                            await _openEmployeeSheet(employee: employee);
                          },
                          onDelete: () => _confirmDelete(employee),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
