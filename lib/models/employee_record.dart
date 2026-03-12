import 'package:flutter/material.dart';

import '../utils/colors.dart';

class EmployeeRecord {
  EmployeeRecord({
    required this.name,
    required this.email,
    required this.phone,
    required this.color,
  });

  String name;
  String email;
  String phone;
  Color color;
}

final List<EmployeeRecord> kEmployees = [
  EmployeeRecord(
    name: 'Emma Carter',
    email: 'employee@email.com',
    phone: '(514) 555-0134',
    color: kEmployeePickerColors[6],
  ),
  EmployeeRecord(
    name: 'Noah Tremblay',
    email: 'employee@email.com',
    phone: '(514) 555-0148',
    color: kEmployeePickerColors[1],
  ),
  EmployeeRecord(
    name: 'Olivia Martin',
    email: 'employee@email.com',
    phone: '(514) 555-0162',
    color: kEmployeePickerColors[2],
  ),
  EmployeeRecord(
    name: 'Liam Roy',
    email: 'employee@email.com',
    phone: '(514) 555-0189',
    color: kEmployeePickerColors[3],
  ),
  EmployeeRecord(
    name: 'Charlotte Gagnon',
    email: 'employee@email.com',
    phone: '(514) 555-0197',
    color: kEmployeePickerColors[7],
  ),
];



String employeeInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) {
    final first = parts.first;
    return first.substring(0, first.length >= 2 ? 2 : 1).toUpperCase();
  }
  return (parts.first[0] + parts[1][0]).toUpperCase();
}

extension EmployeeRecordX on EmployeeRecord {
  String get initials => employeeInitials(name);
}

EmployeeRecord? employeeByName(String name) {
  final normalized = name.trim().toLowerCase();
  for (final employee in kEmployees) {
    if (employee.name.trim().toLowerCase() == normalized) {
      return employee;
    }
  }
  return null;
}

Color employeeColorForName(String name, {Color fallback = const Color(0xFFDCD4F8)}) {
  return employeeByName(name)?.color ?? fallback;
}

String employeeInitialsForName(String name) {
  return employeeByName(name)?.initials ?? employeeInitials(name);
}
