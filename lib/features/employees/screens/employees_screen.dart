import 'package:flutter/material.dart';

import 'package:scheduling/core/utils/app_text.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/features/employees/services/user_service.dart';
import 'package:scheduling/features/employees/widgets/employee_card.dart';
import 'package:scheduling/features/employees/widgets/employee_details_sheet.dart';
import 'package:scheduling/features/employees/widgets/employee_form_sheet.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';

class AddEmployeePage extends StatefulWidget {
  const AddEmployeePage({super.key});

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

    if (result == 'deleted') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Employee deleted'))),
      );
    } else if (result == true) {
      final messageKey = employee == null
          ? 'Employee added successfully'
          : 'Employee updated successfully';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, messageKey))),
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

    if (!mounted || result != 'deleted') return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, 'Employee deleted'))),
    );
  }

  Future<void> _confirmDelete(EmployeeRecord employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'Delete employee')),
        content: Text(
          tr(ctx, 'Are you sure you want to delete this employee?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'Delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _userService.deleteEmployee(employee.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, 'Employee deleted'))),
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _openEmployeeSheet,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  Expanded(
                    child: Text(
                      tr(context, 'Employees'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: formInputDecoration(
                  context,
                  tr(context, 'Search by name or phone number...'),
                ).copyWith(prefixIcon: const Icon(Icons.search)),
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
                        child: Text(tr(context, 'Error loading employees')),
                      );
                    }

                    final employees = _filterEmployees(snapshot.data ?? []);
                    if (employees.isEmpty) {
                      return Center(
                        child: Text(tr(context, 'No employees found')),
                      );
                    }

                    return ListView.separated(
                      itemCount: employees.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final employee = employees[index];
                        return EmployeeCard(
                          employee: employee,
                          onTap: () => _showEmployeeDetails(employee),
                          onEdit: () => _openEmployeeSheet(employee: employee),
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
