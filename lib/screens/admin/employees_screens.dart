import 'package:flutter/material.dart';

import '../../models/employee_record.dart';
import '../../utils/colors.dart';
import '../../widgets/admin_drawers.dart';

class AdminEmployeesPage extends StatefulWidget {
  const AdminEmployeesPage({super.key});

  @override
  State<AdminEmployeesPage> createState() => _AdminEmployeesPageState();
}

class _AdminEmployeesPageState extends State<AdminEmployeesPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EmployeeRecord> get filteredEmployees {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return kEmployees;
    return kEmployees.where((employee) {
      return employee.name.toLowerCase().contains(query) ||
          employee.phone.toLowerCase().contains(query) ||
          employee.email.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final employees = filteredEmployees;

    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      endDrawer: AdminMenuDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>  CreateEmployeePage(),
            ),
          );
          setState(() {});
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
                    'Edit Employees',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
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
                  hintText: 'Search by name or phone number',
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
                child: ListView.separated(
                  itemCount: employees.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final employee = employees[index];
                    return _EmployeeCard(
                      employee: employee,
                      onEdit: () async {
                        await showEditEmployeePopup(context, employee: employee);
                        setState(() {});
                      },
                      onDelete: () {
                        setState(() {
                          kEmployees.remove(employee);
                        });
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

/* ---------------- EMPLOYEES DARK ---------------- */

class AdminEmployeesDarkPage extends StatefulWidget {
  const AdminEmployeesDarkPage({super.key});

  @override
  State<AdminEmployeesDarkPage> createState() => _AdminEmployeesDarkPageState();
}

class _AdminEmployeesDarkPageState extends State<AdminEmployeesDarkPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EmployeeRecord> get filteredEmployees {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return kEmployees;
    return kEmployees.where((employee) {
      return employee.name.toLowerCase().contains(query) ||
          employee.phone.toLowerCase().contains(query) ||
          employee.email.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final employees = filteredEmployees;

    return Scaffold(
      backgroundColor: Colors.black,
      endDrawer: AdminMenuDrawerDark(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateEmployeeDarkPage(),
            ),
          );
          setState(() {});
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
                    'Edit Employees',
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
                      child: Icon(Icons.menu, size: 28, color: Colors.white),
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
                  hintText: 'Search by name or phone number',
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
                child: ListView.separated(
                  itemCount: employees.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final employee = employees[index];
                    return _EmployeeCardDark(
                      employee: employee,
                      onEdit: () async {
                        await showEditEmployeeDarkPopup(context, employee: employee);
                        setState(() {});
                      },
                      onDelete: () {
                        setState(() {
                          kEmployees.remove(employee);
                        });
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

/* ---------------- CREATE EMPLOYEE LIGHT ---------------- */

class CreateEmployeePage extends StatefulWidget {
  const CreateEmployeePage({super.key});

  @override
  State<CreateEmployeePage> createState() => _CreateEmployeePageState();
}

class _CreateEmployeePageState extends State<CreateEmployeePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  Color _selectedColor = kEmployeePickerColors[1];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
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
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Create Employee',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(width: 48),
                ],
              ),
              SizedBox(height: 10),
              Text('Enter username and email'),
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
                    Text('Username'),
                    SizedBox(height: 8),
                    _employeeFormField(controller: _nameController, hintText: 'Value'),
                    SizedBox(height: 14),
                    Text('Email'),
                    SizedBox(height: 8),
                    _employeeFormField(controller: _emailController, hintText: 'Value'),
                    SizedBox(height: 14),
                    Text('Phone number'),
                    SizedBox(height: 8),
                    _employeeFormField(controller: _phoneController, hintText: 'Value'),
                    SizedBox(height: 18),
                    Text('Employee Color'),
                    SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: kEmployeePickerColors.map((color) {
                        final isSelected = _selectedColor == color;
                        return _ColorDot(
                          color: color,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() {
                              _selectedColor = color;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            kEmployees.add(
                              EmployeeRecord(
                                name: _nameController.text.trim().isEmpty
                                    ? 'Employee name'
                                    : _nameController.text.trim(),
                                email: _emailController.text.trim().isEmpty
                                    ? 'employee@email.com'
                                    : _emailController.text.trim(),
                                phone: _phoneController.text.trim().isEmpty
                                    ? '(000) 000-0000'
                                    : _phoneController.text.trim(),
                                color: _selectedColor,
                              ),
                            );
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text('Create Employee'),
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
  const CreateEmployeeDarkPage({super.key});

  @override
  State<CreateEmployeeDarkPage> createState() => _CreateEmployeeDarkPageState();
}

class _CreateEmployeeDarkPageState extends State<CreateEmployeeDarkPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  Color _selectedColor = kEmployeePickerColors[1];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
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
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      'Create Employee',
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
              Text('Enter username and email', style: TextStyle(color: Colors.white70)),
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
                    Text('Username', style: TextStyle(color: Colors.white)),
                    SizedBox(height: 8),
                    _employeeFormFieldDark(controller: _nameController, hintText: 'Value'),
                    SizedBox(height: 14),
                    Text('Email', style: TextStyle(color: Colors.white)),
                    SizedBox(height: 8),
                    _employeeFormFieldDark(controller: _emailController, hintText: 'Value'),
                    SizedBox(height: 14),
                    Text('Phone number', style: TextStyle(color: Colors.white)),
                    SizedBox(height: 8),
                    _employeeFormFieldDark(controller: _phoneController, hintText: 'Value'),
                    SizedBox(height: 18),
                    Text('Employee Color', style: TextStyle(color: Colors.white)),
                    SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: kEmployeePickerColors.map((color) {
                        final isSelected = _selectedColor == color;
                        return _ColorDot(
                          color: color,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() {
                              _selectedColor = color;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            kEmployees.add(
                              EmployeeRecord(
                                name: _nameController.text.trim().isEmpty
                                    ? 'Employee name'
                                    : _nameController.text.trim(),
                                email: _emailController.text.trim().isEmpty
                                    ? 'employee@email.com'
                                    : _emailController.text.trim(),
                                phone: _phoneController.text.trim().isEmpty
                                    ? '(000) 000-0000'
                                    : _phoneController.text.trim(),
                                color: _selectedColor,
                              ),
                            );
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text('Create Employee'),
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

/* ---------------- SETTINGS LIGHT ---------------- */

class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      endDrawer: AdminMenuDrawer(),
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
                    'Settings',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
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
              SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFFE1E1E1)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.description_outlined),
                      title: Text('Change Font Size'),
                      onTap: () {},
                    ),
                    Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.dark_mode_outlined),
                      title: Text('Change to Dark Mode'),
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AdminSettingsDarkPage(),
                          ),
                        );
                      },
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

/* ---------------- SETTINGS DARK ---------------- */

class AdminSettingsDarkPage extends StatelessWidget {
  const AdminSettingsDarkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      endDrawer: AdminMenuDrawerDark(),
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
                    'Settings',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Spacer(),
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Scaffold.of(context).openEndDrawer(),
                      child: Icon(Icons.menu, size: 28, color: Colors.white),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Color(0xFF121212),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFF2A2A2A)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.description_outlined, color: Colors.white70),
                      title: Text('Change Font Size', style: TextStyle(color: Colors.white)),
                      onTap: () {},
                    ),
                    Divider(height: 1, color: Color(0xFF2A2A2A)),
                    ListTile(
                      leading: Icon(Icons.light_mode_outlined, color: Colors.white70),
                      title: Text('Change to Light Mode', style: TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AdminSettingsPage(),
                          ),
                        );
                      },
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

class _EmployeeCard extends StatelessWidget {
  final EmployeeRecord employee;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EmployeeCard({
    required this.employee,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _EmployeeCardDark extends StatelessWidget {
  final EmployeeRecord employee;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EmployeeCardDark({
    required this.employee,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
              color: employee.color.withOpacity(0.9),
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
                  style: TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: Icon(Icons.edit_outlined, size: 20, color: Colors.white70),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, size: 20, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

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
            color: isSelected ? kPurple : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: isSelected
            ? Icon(Icons.check, size: 12, color: Colors.white)
            : null,
      ),
    );
  }
}

Widget _employeeFormField({
  required TextEditingController controller,
  required String hintText,
}) {
  return TextField(
    controller: controller,
    decoration: InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFFD8D8D8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kPurple),
      ),
    ),
  );
}

Widget _employeeFormFieldDark({
  required TextEditingController controller,
  required String hintText,
}) {
  return TextField(
    controller: controller,
    style: TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.white38),
      filled: true,
      fillColor: Color(0xFF171717),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFF2D2D2D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kPurple),
      ),
    ),
  );
}

Future<void> showEditEmployeePopup(
    BuildContext context, {
      required EmployeeRecord employee,
    }) async {
  final nameController = TextEditingController(text: employee.name);
  final phoneController = TextEditingController(text: employee.phone);
  final emailController = TextEditingController(text: employee.email);
  Color selectedColor = employee.color;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
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
                      child: Divider(thickness: 4, color: Color(0xFFD0D0D0)),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Edit Employee',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 18),
                    _employeeFormField(controller: nameController, hintText: 'name'),
                    SizedBox(height: 12),
                    _employeeFormField(controller: phoneController, hintText: 'Phone number'),
                    SizedBox(height: 12),
                    _employeeFormField(controller: emailController, hintText: 'Email'),
                    SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Employee Color',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: kEmployeePickerColors.map((color) {
                        return _ColorDot(
                          color: color,
                          isSelected: selectedColor.value == color.value,
                          onTap: () {
                            setModalState(() {
                              selectedColor = color;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          employee.name = nameController.text.trim().isEmpty
                              ? employee.name
                              : nameController.text.trim();
                          employee.phone = phoneController.text.trim().isEmpty
                              ? employee.phone
                              : phoneController.text.trim();
                          employee.email = emailController.text.trim().isEmpty
                              ? employee.email
                              : emailController.text.trim();
                          employee.color = selectedColor;
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text('Update Employee'),
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

Future<void> showEditEmployeeDarkPopup(
    BuildContext context, {
      required EmployeeRecord employee,
    }) async {
  final nameController = TextEditingController(text: employee.name);
  final phoneController = TextEditingController(text: employee.phone);
  final emailController = TextEditingController(text: employee.email);
  Color selectedColor = employee.color;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
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
                      child: Divider(thickness: 4, color: Color(0xFF3A3A3A)),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Edit Employee',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 18),
                    _employeeFormFieldDark(controller: nameController, hintText: 'name'),
                    SizedBox(height: 12),
                    _employeeFormFieldDark(controller: phoneController, hintText: 'Phone number'),
                    SizedBox(height: 12),
                    _employeeFormFieldDark(controller: emailController, hintText: 'Email'),
                    SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Employee Color',
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
                          isSelected: selectedColor.value == color.value,
                          onTap: () {
                            setModalState(() {
                              selectedColor = color;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          employee.name = nameController.text.trim().isEmpty
                              ? employee.name
                              : nameController.text.trim();
                          employee.phone = phoneController.text.trim().isEmpty
                              ? employee.phone
                              : phoneController.text.trim();
                          employee.email = emailController.text.trim().isEmpty
                              ? employee.email
                              : emailController.text.trim();
                          employee.color = selectedColor;
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text('Update Employee'),
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

/* ---------------- POPUP ---------------- */

