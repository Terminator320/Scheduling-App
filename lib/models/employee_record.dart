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

