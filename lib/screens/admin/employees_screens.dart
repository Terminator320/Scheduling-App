import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/employee_record.dart';
import '../../services/user_service.dart';
import '../../utils/app_text.dart';
import '../../utils/colors.dart';
import '../../widgets/admin_drawers.dart';

class AdminEmployeesPage extends StatefulWidget {
  const AdminEmployeesPage({super.key});

  @override
  State<AdminEmployeesPage> createState() => _AdminEmployeesPageState();
}

class _AdminEmployeesPageState extends State<AdminEmployeesPage> {
  final TextEditingController _searchController = TextEditingController();

  Future<bool> _loadCanGrantAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return UserService.canGrantAdminForUid(uid);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EmployeeRecord> _filterEmployees(List<EmployeeRecord> employees) {
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) return employees;

    return employees.where((employee) {
      return employee.name.toLowerCase().contains(query) ||
          employee.phone.toLowerCase().contains(query) ||
          employee.email.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _loadCanGrantAdmin(),
      builder: (context, permissionSnapshot) {
        final canGrantAdmin = permissionSnapshot.data ?? false;

        return Scaffold(
          backgroundColor: Color(0xFFF5F5F5),
          endDrawer: AdminMenuDrawer(),
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CreateEmployeePage(
                    canGrantAdmin: canGrantAdmin,
                  ),
                ),
              );
            },
            backgroundColor: kPurple,
            shape: CircleBorder(),
            child: Icon(Icons.add, color: Colors.white, size: 30),
          ),
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Column(
                children: [
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Spacer(),
                      Text(
                        tr(context, 'Edit Employees'),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Spacer(),
                      Builder(
                        builder: (context) => GestureDetector(
                          onTap: () => Scaffold.of(context).openEndDrawer(),
                          child: Icon(Icons.menu, size: 28),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText:
                      tr(context, 'Search by name or phone number'),
                      hintStyle: TextStyle(color: Color(0xFF9A9A9A)),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Color(0xFFE0E0E0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: kPurple),
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<List<EmployeeRecord>>(
                      stream: UserService.employeesStream(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              tr(context, 'Error loading employees'),
                            ),
                          );
                        }

                        final employees = _filterEmployees(snapshot.data ?? []);

                        if (employees.isEmpty) {
                          return Center(
                            child: Text(
                              tr(context, 'No employees found'),
                            ),
                          );
                        }

                        return ListView.separated(
                          itemCount: employees.length,
                          separatorBuilder: (_, _) =>
                          SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final employee = employees[index];

                            return _EmployeeCard(
                              employee: employee,
                              onTap: () async {
                                await showEmployeeDetailsPopup(
                                  context,
                                  employee: employee,
                                );
                              },
                              onEdit: () async {
                                await showEditEmployeePopup(
                                  context,
                                  employee: employee,
                                  canGrantAdmin: canGrantAdmin,
                                );
                              },
                              onDelete: () async {
                                final shouldDelete =
                                await _showDeleteEmployeeDialog(context);

                                if (shouldDelete == true) {
                                  await UserService.deleteEmployee(employee.id);
                                }
                              },
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
      },
    );
  }
}

/* ---------------- EMPLOYEES DARK ---------------- */

class AdminEmployeesDarkPage extends StatefulWidget {
  const AdminEmployeesDarkPage({super.key});

  @override
  State<AdminEmployeesDarkPage> createState() =>
      _AdminEmployeesDarkPageState();
}

class _AdminEmployeesDarkPageState extends State<AdminEmployeesDarkPage> {
  final TextEditingController _searchController = TextEditingController();

  Future<bool> _loadCanGrantAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return UserService.canGrantAdminForUid(uid);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EmployeeRecord> _filterEmployees(List<EmployeeRecord> employees) {
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) return employees;

    return employees.where((employee) {
      return employee.name.toLowerCase().contains(query) ||
          employee.phone.toLowerCase().contains(query) ||
          employee.email.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _loadCanGrantAdmin(),
      builder: (context, permissionSnapshot) {
        final canGrantAdmin = permissionSnapshot.data ?? false;

        return Scaffold(
          backgroundColor: Colors.black,
          endDrawer: AdminMenuDrawerDark(),
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CreateEmployeeDarkPage(
                    canGrantAdmin: canGrantAdmin,
                  ),
                ),
              );
            },
            backgroundColor: kPurple,
            shape: CircleBorder(),
            child: Icon(Icons.add, color: Colors.white, size: 30),
          ),
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Column(
                children: [
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Spacer(),
                      Text(
                        tr(context, 'Edit Employees'),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      Spacer(),
                      Builder(
                        builder: (context) => GestureDetector(
                          onTap: () => Scaffold.of(context).openEndDrawer(),
                          child: Icon(
                            Icons.menu,
                            size: 28,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    style: TextStyle(color: Colors.white),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText:
                      tr(context, 'Search by name or phone number'),
                      hintStyle: TextStyle(color: Color(0xFF9A9A9A)),
                      filled: true,
                      fillColor: Color(0xFF171717),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Color(0xFF2D2D2D)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: kPurple),
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<List<EmployeeRecord>>(
                      stream: UserService.employeesStream(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              tr(context, 'Error loading employees'),
                              style: TextStyle(color: Colors.white),
                            ),
                          );
                        }

                        final employees = _filterEmployees(snapshot.data ?? []);

                        if (employees.isEmpty) {
                          return Center(
                            child: Text(
                              tr(context, 'No employees found'),
                              style: TextStyle(color: Colors.white),
                            ),
                          );
                        }

                        return ListView.separated(
                          itemCount: employees.length,
                          separatorBuilder: (_, _) =>
                          SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final employee = employees[index];

                            return _EmployeeCardDark(
                              employee: employee,
                              onTap: () async {
                                await showEmployeeDetailsDarkPopup(
                                  context,
                                  employee: employee,
                                );
                              },
                              onEdit: () async {
                                await showEditEmployeeDarkPopup(
                                  context,
                                  employee: employee,
                                  canGrantAdmin: canGrantAdmin,
                                );
                              },
                              onDelete: () async {
                                final shouldDelete =
                                await _showDeleteEmployeeDialogDark(
                                  context,
                                );

                                if (shouldDelete == true) {
                                  await UserService.deleteEmployee(employee.id);
                                }
                              },
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
      },
    );
  }
}

/* ---------------- CREATE EMPLOYEE LIGHT ---------------- */

class CreateEmployeePage extends StatefulWidget {
  const CreateEmployeePage({
    super.key,
    required this.canGrantAdmin,
  });

  final bool canGrantAdmin;

  @override
  State<CreateEmployeePage> createState() => _CreateEmployeePageState();
}

class _CreateEmployeePageState extends State<CreateEmployeePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  Color _selectedColor = kEmployeePickerColors[1];
  bool _isLoading = false;
  bool _giveAdminAccess = false;
  String? _pageError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_pageError != null) {
      setState(() {
        _pageError = null;
      });
    }
  }

  Future<void> _createEmployee() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || email.isEmpty) {
      setState(() {
        _pageError = tr(context, 'Name and email are required');
      });
      return;
    }

    setState(() {
      _pageError = null;
      _isLoading = true;
    });

    try {
      await UserService.addEmployee(
        name: name,
        email: email,
        phone: phone,
        colorValue: _selectedColor.toARGB32().toString(),
        isAdmin: widget.canGrantAdmin ? _giveAdminAccess : false,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _pageError = _friendlyErrorMessage(context, e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _friendlyErrorMessage(BuildContext context, Object e) {
    final message = e.toString();

    if (message.contains('already exists')) {
      return tr(context, 'An employee with this email already exists');
    }

    return tr(context, 'Could not create employee');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  Expanded(
                    child: Text(
                      tr(context, 'Create Employee'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(width: 48),
                ],
              ),
              SizedBox(height: 10),
              Text(tr(context, 'Enter username and email')),
              SizedBox(height: 24),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFFE1E1E1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 8),
                    _employeeFormField(
                      context: context,
                      controller: _nameController,
                      hintText: 'Name',
                      onChanged: (_) => _clearError(),
                    ),
                    SizedBox(height: 14),
                    _employeeFormField(
                      context: context,
                      controller: _emailController,
                      hintText: 'Email',
                      onChanged: (_) => _clearError(),
                    ),
                    SizedBox(height: 14),
                    _employeeFormField(
                      context: context,
                      controller: _phoneController,
                      hintText: 'Phone number',
                      onChanged: (_) => _clearError(),
                    ),
                    if (_pageError != null) ...[
                      SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Color(0xFFFFEAEA),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Color(0xFFFFB3B3)),
                        ),
                        child: Text(
                          _pageError!,
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: 18),
                    Text(tr(context, 'Employee Color')),
                    SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: kEmployeePickerColors.map((color) {
                        final isSelected = _selectedColor == color;

                        return _ColorDot(
                          color: color,
                          isSelected: isSelected,
                          onTap: _isLoading
                              ? null
                              : () {
                            setState(() {
                              _selectedColor = color;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (widget.canGrantAdmin) ...[
                      SizedBox(height: 18),
                      CheckboxListTile(
                        value: _giveAdminAccess,
                        onChanged: _isLoading
                            ? null
                            : (value) {
                          setState(() {
                            _giveAdminAccess = value ?? false;
                          });
                        },
                        title: Text(
                          tr(context, 'Give admin mode access'),
                        ),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                    SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _createEmployee,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _isLoading
                            ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                            : Text(tr(context, 'Create Employee')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- CREATE EMPLOYEE DARK ---------------- */

class CreateEmployeeDarkPage extends StatefulWidget {
  const CreateEmployeeDarkPage({
    super.key,
    required this.canGrantAdmin,
  });

  final bool canGrantAdmin;

  @override
  State<CreateEmployeeDarkPage> createState() => _CreateEmployeeDarkPageState();
}

class _CreateEmployeeDarkPageState extends State<CreateEmployeeDarkPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  Color _selectedColor = kEmployeePickerColors[1];
  bool _isLoading = false;
  bool _giveAdminAccess = false;
  String? _pageError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_pageError != null) {
      setState(() {
        _pageError = null;
      });
    }
  }

  Future<void> _createEmployee() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || email.isEmpty) {
      setState(() {
        _pageError = tr(context, 'Name and email are required');
      });
      return;
    }

    setState(() {
      _pageError = null;
      _isLoading = true;
    });

    try {
      await UserService.addEmployee(
        name: name,
        email: email,
        phone: phone,
        colorValue: _selectedColor.toARGB32().toString(),
        isAdmin: widget.canGrantAdmin ? _giveAdminAccess : false,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _pageError = _friendlyErrorMessage(context, e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _friendlyErrorMessage(BuildContext context, Object e) {
    final message = e.toString();

    if (message.contains('already exists')) {
      return tr(context, 'An employee with this email already exists');
    }

    return tr(context, 'Could not create employee');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tr(context, 'Create Employee'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(width: 48),
                ],
              ),
              SizedBox(height: 10),
              Text(
                tr(context, 'Enter username and email'),
                style: TextStyle(color: Colors.white70),
              ),
              SizedBox(height: 24),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color(0xFF121212),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFF2A2A2A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 8),
                    _employeeFormFieldDark(
                      context: context,
                      controller: _nameController,
                      hintText: 'Name',
                      onChanged: (_) => _clearError(),
                    ),
                    SizedBox(height: 14),
                    _employeeFormFieldDark(
                      context: context,
                      controller: _emailController,
                      hintText: 'Email',
                      onChanged: (_) => _clearError(),
                    ),
                    SizedBox(height: 14),
                    _employeeFormFieldDark(
                      context: context,
                      controller: _phoneController,
                      hintText: 'Phone number',
                      onChanged: (_) => _clearError(),
                    ),
                    if (_pageError != null) ...[
                      SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Color(0xFF2A1212),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Color(0xFF5A2A2A)),
                        ),
                        child: Text(
                          _pageError!,
                          style: TextStyle(
                            color: Color(0xFFFF8A8A),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: 18),
                    Text(
                      tr(context, 'Employee Color'),
                      style: TextStyle(color: Colors.white),
                    ),
                    SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: kEmployeePickerColors.map((color) {
                        final isSelected = _selectedColor == color;

                        return _ColorDot(
                          color: color,
                          isSelected: isSelected,
                          onTap: _isLoading
                              ? null
                              : () {
                            setState(() {
                              _selectedColor = color;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (widget.canGrantAdmin) ...[
                      SizedBox(height: 18),
                      CheckboxListTile(
                        value: _giveAdminAccess,
                        onChanged: _isLoading
                            ? null
                            : (value) {
                          setState(() {
                            _giveAdminAccess = value ?? false;
                          });
                        },
                        title: Text(
                          tr(context, 'Give admin mode access'),
                          style: TextStyle(color: Colors.white),
                        ),
                        checkColor: Colors.white,
                        activeColor: kPurple,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                    SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _createEmployee,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _isLoading
                            ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                            : Text(tr(context, 'Create Employee')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _employeeFormField({
  required BuildContext context,
  required TextEditingController controller,
  required String hintText,
  ValueChanged<String>? onChanged,
}) {
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(
        color: Colors.black87,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        labelText: tr(context, hintText),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: TextStyle(
          color: Color(0xFF8E8E93),
          fontSize: 14,
        ),
        floatingLabelStyle: TextStyle(
          color: kPurple,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Color(0xFFE5E5EA),
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: kPurple,
            width: 2,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Color(0xFFE5E5EA),
            width: 1.2,
          ),
        ),
      ),
    ),
  );
}

Widget _employeeFormFieldDark({
  required BuildContext context,
  required TextEditingController controller,
  required String hintText,
  ValueChanged<String>? onChanged,
}) {
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.35),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(
        color: Colors.white,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        labelText: tr(context, hintText),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: TextStyle(
          color: Colors.white38,
          fontSize: 14,
        ),
        floatingLabelStyle: TextStyle(
          color: kPurple,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: Color(0xFF171717),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Color(0xFF2D2D2D),
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: kPurple,
            width: 2,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Color(0xFF2D2D2D),
            width: 1.2,
          ),
        ),
      ),
    ),
  );
}

/* ---------------- EMPLOYEE CARDS LIGHT ---------------- */

class _EmployeeCard extends StatelessWidget {
  final EmployeeRecord employee;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EmployeeCard({
    required this.employee,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: employeeCardColor(employee.color),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      employee.email,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
                icon: Icon(Icons.edit_outlined, size: 20),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- EMPLOYEE CARDS DARK ---------------- */

class _EmployeeCardDark extends StatelessWidget {
  final EmployeeRecord employee;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EmployeeCardDark({
    required this.employee,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Color(0xFF171717),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Color(0xFF2A2A2A)),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 44,
                decoration: BoxDecoration(
                  color: employee.color.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      employee.email,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
                icon: Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: Colors.white70,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback? onTap;

  const _ColorDot({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.black : Colors.transparent,
            width: 2,
          ),
        ),
        child: isSelected
            ? Icon(
          Icons.check,
          size: 14,
          color: Colors.white,
        )
            : null,
      ),
    );
  }
}

/* ---------------- DETAIL FIELDS ---------------- */

Widget _detailField({required String value}) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    decoration: BoxDecoration(
      color: Color(0xFFF3F3F3),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Color(0xFFD2D2D2)),
    ),
    child: Text(
      value,
      style: TextStyle(
        fontSize: 15,
        color: Color(0xFF7A7A7A),
        fontWeight: FontWeight.w400,
      ),
    ),
  );
}

Widget _detailFieldDark({required String value}) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    decoration: BoxDecoration(
      color: Color(0xFF171717),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Color(0xFF2D2D2D)),
    ),
    child: Text(
      value,
      style: TextStyle(
        fontSize: 15,
        color: Colors.white70,
        fontWeight: FontWeight.w400,
      ),
    ),
  );
}

/* ---------------- EMPLOYEE DETAILS POPUP LIGHT ---------------- */

Future<void> showEmployeeDetailsPopup(
    BuildContext context, {
      required EmployeeRecord employee,
    }) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 22),
          decoration: BoxDecoration(
            color: Color(0xFFF3F3F3),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Color(0xFFD1D1D1),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              SizedBox(height: 18),
              Text(
                tr(context, 'Employee details'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              SizedBox(height: 20),
              _detailField(
                value: employee.name.isEmpty
                    ? tr(context, 'name')
                    : employee.name,
              ),
              SizedBox(height: 12),
              _detailField(
                value: employee.phone.isEmpty
                    ? tr(context, 'Phone number')
                    : employee.phone,
              ),
              SizedBox(height: 12),
              _detailField(
                value: employee.email.isEmpty
                    ? tr(context, 'Email')
                    : employee.email,
              ),
              SizedBox(height: 12),
              _employeeColorPreview(
                context: context,
                color: employee.color,
                isDark: false,
              ),
            ],
          ),
        ),
      );
    },
  );
}

/* ---------------- EMPLOYEE DETAILS POPUP DARK ---------------- */

Future<void> showEmployeeDetailsDarkPopup(
    BuildContext context, {
      required EmployeeRecord employee,
    }) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 22),
          decoration: BoxDecoration(
            color: Color(0xFF121212),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Color(0xFF2A2A2A)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              SizedBox(height: 18),
              Text(
                tr(context, 'Employee details'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 20),
              _detailFieldDark(
                value: employee.name.isEmpty
                    ? tr(context, 'name')
                    : employee.name,
              ),
              SizedBox(height: 12),
              _detailFieldDark(
                value: employee.phone.isEmpty
                    ? tr(context, 'Phone number')
                    : employee.phone,
              ),
              SizedBox(height: 12),
              _detailFieldDark(
                value: employee.email.isEmpty
                    ? tr(context, 'Email')
                    : employee.email,
              ),
              SizedBox(height: 12),
              _employeeColorPreview(
                context: context,
                color: employee.color,
                isDark: true,
              ),
            ],
          ),
        ),
      );
    },
  );
}

/* ---------------- EDIT POPUP LIGHT ---------------- */

Future<void> showEditEmployeePopup(
    BuildContext context, {
      required EmployeeRecord employee,
      required bool canGrantAdmin,
    }) async {
  final nameController = TextEditingController(text: employee.name);
  final phoneController = TextEditingController(text: employee.phone);
  final emailController = TextEditingController(text: employee.email);
  Color selectedColor = employee.color;
  bool giveAdminAccess = employee.isAdmin;
  bool isSaving = false;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> updateEmployee() async {
            final updatedName = nameController.text.trim().isEmpty
                ? employee.name
                : nameController.text.trim();

            final updatedPhone = phoneController.text.trim().isEmpty
                ? employee.phone
                : phoneController.text.trim();

            final updatedEmail = emailController.text.trim().isEmpty
                ? employee.email
                : emailController.text.trim().toLowerCase();

            setModalState(() {
              isSaving = true;
            });

            try {
              await UserService.updateEmployee(
                docId: employee.id,
                name: updatedName,
                email: updatedEmail,
                phone: updatedPhone,
                colorValue: selectedColor.toARGB32().toString(),
                isAdmin: canGrantAdmin ? giveAdminAccess : null,
              );

              if (!context.mounted) return;
              Navigator.pop(context);
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(e.toString())),
              );
            } finally {
              if (context.mounted) {
                setModalState(() {
                  isSaving = false;
                });
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.fromLTRB(18, 12, 18, 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Divider(
                        thickness: 4,
                        color: Color(0xFFD0D0D0),
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      tr(context, 'Edit Employee'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 18),
                    _employeeFormField(
                      context: context,
                      controller: nameController,
                      hintText: 'name',
                    ),
                    SizedBox(height: 12),
                    _employeeFormField(
                      context: context,
                      controller: phoneController,
                      hintText: 'Phone number',
                    ),
                    SizedBox(height: 12),
                    _employeeFormField(
                      context: context,
                      controller: emailController,
                      hintText: 'Email',
                    ),
                    SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tr(context, 'Employee Color'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: kEmployeePickerColors.map((color) {
                        return _ColorDot(
                          color: color,
                          isSelected: selectedColor == color,
                          onTap: () {
                            setModalState(() {
                              selectedColor = color;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (canGrantAdmin) ...[
                      SizedBox(height: 16),
                      CheckboxListTile(
                        value: giveAdminAccess,
                        onChanged: (value) {
                          setModalState(() {
                            giveAdminAccess = value ?? false;
                          });
                        },
                        title: Text(
                          tr(context, 'Give admin mode access'),
                        ),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSaving ? null : updateEmployee,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isSaving
                            ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                            : Text(tr(context, 'Update Employee')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

/* ---------------- EDIT POPUP DARK ---------------- */

Future<void> showEditEmployeeDarkPopup(
    BuildContext context, {
      required EmployeeRecord employee,
      required bool canGrantAdmin,
    }) async {
  final nameController = TextEditingController(text: employee.name);
  final phoneController = TextEditingController(text: employee.phone);
  final emailController = TextEditingController(text: employee.email);
  Color selectedColor = employee.color;
  bool giveAdminAccess = employee.isAdmin;
  bool isSaving = false;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> updateEmployee() async {
            final updatedName = nameController.text.trim().isEmpty
                ? employee.name
                : nameController.text.trim();

            final updatedPhone = phoneController.text.trim().isEmpty
                ? employee.phone
                : phoneController.text.trim();

            final updatedEmail = emailController.text.trim().isEmpty
                ? employee.email
                : emailController.text.trim().toLowerCase();

            setModalState(() {
              isSaving = true;
            });

            try {
              await UserService.updateEmployee(
                docId: employee.id,
                name: updatedName,
                email: updatedEmail,
                phone: updatedPhone,
                colorValue: selectedColor.toARGB32().toString(),
                isAdmin: canGrantAdmin ? giveAdminAccess : null,
              );

              if (!context.mounted) return;
              Navigator.pop(context);
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(e.toString())),
              );
            } finally {
              if (context.mounted) {
                setModalState(() {
                  isSaving = false;
                });
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.fromLTRB(18, 12, 18, 22),
                decoration: BoxDecoration(
                  color: Color(0xFF121212),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Divider(
                        thickness: 4,
                        color: Color(0xFF3A3A3A),
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      tr(context, 'Edit Employee'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 18),
                    _employeeFormFieldDark(
                      context: context,
                      controller: nameController,
                      hintText: 'name',
                    ),
                    SizedBox(height: 12),
                    _employeeFormFieldDark(
                      context: context,
                      controller: phoneController,
                      hintText: 'Phone number',
                    ),
                    SizedBox(height: 12),
                    _employeeFormFieldDark(
                      context: context,
                      controller: emailController,
                      hintText: 'Email',
                    ),
                    SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tr(context, 'Employee Color'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: kEmployeePickerColors.map((color) {
                        return _ColorDot(
                          color: color,
                          isSelected: selectedColor == color,
                          onTap: () {
                            setModalState(() {
                              selectedColor = color;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (canGrantAdmin) ...[
                      SizedBox(height: 16),
                      CheckboxListTile(
                        value: giveAdminAccess,
                        onChanged: (value) {
                          setModalState(() {
                            giveAdminAccess = value ?? false;
                          });
                        },
                        title: Text(
                          tr(context, 'Give admin mode access'),
                          style: TextStyle(color: Colors.white),
                        ),
                        checkColor: Colors.white,
                        activeColor: kPurple,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSaving ? null : updateEmployee,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isSaving
                            ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                            : Text(tr(context, 'Update Employee')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Future<bool?> _showDeleteEmployeeDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr(context, 'Delete employee')),
      content: Text(
        tr(context, 'Are you sure you want to delete this employee?'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr(context, 'Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(tr(context, 'Delete')),
        ),
      ],
    ),
  );
}

Future<bool?> _showDeleteEmployeeDialogDark(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Color(0xFF121212),
      title: Text(
        tr(context, 'Delete employee'),
        style: TextStyle(color: Colors.white),
      ),
      content: Text(
        tr(context, 'Are you sure you want to delete this employee?'),
        style: TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr(context, 'Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(tr(context, 'Delete')),
        ),
      ],
    ),
  );
}

Widget _employeeColorPreview({
  required BuildContext context,
  required Color color,
  required bool isDark,
}) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    decoration: BoxDecoration(
      color: isDark ? Color(0xFF171717) : Color(0xFFF3F3F3),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: isDark ? Color(0xFF2D2D2D) : Color(0xFFD2D2D2),
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 10),
        Text(
          tr(context, 'Employee color'),
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white70 : Color(0xFF7A7A7A),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    ),
  );
}