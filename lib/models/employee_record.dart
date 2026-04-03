import 'package:flutter/material.dart';

class EmployeeRecord {
  EmployeeRecord({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.color,
    required this.role,
    required this.status,
    required this.uid,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final Color color;
  final String role;
  final String status;
  final String uid;

  factory EmployeeRecord.fromMap(
      String id,
      Map<String, dynamic> data,
      ) {
    final colorValue =
        int.tryParse((data['colorValue'] ?? '').toString()) ??
            Colors.blue.toARGB32();

    return EmployeeRecord(
      id: id,
      name: (data['name'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      color: Color(colorValue),
      role: (data['role'] ?? 'employee').toString(),
      status: (data['status'] ?? '').toString(),
      uid: (data['uid'] ?? '').toString(),
    );
  }



  bool get isAdmin => role == 'admin';

}