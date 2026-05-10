import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

void main() {
  group('EmployeeRecord', () {
    test('value equality works (freezed)', () {
      const a = EmployeeRecord(
        id: 'e1',
        name: 'Jane',
        email: 'jane@example.com',
        role: 'admin',
        status: 'active',
      );
      const b = EmployeeRecord(
        id: 'e1',
        name: 'Jane',
        email: 'jane@example.com',
        role: 'admin',
        status: 'active',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith returns a new value with updated fields', () {
      const original = EmployeeRecord(id: 'e1', name: 'Jane');
      final updated = original.copyWith(name: 'Janet');

      expect(updated.id, 'e1');
      expect(updated.name, 'Janet');
      expect(original.name, 'Jane'); // immutable
    });

    test('isAdmin / isActive / isDisabled derive from role + status', () {
      const admin = EmployeeRecord(id: 'e1', role: 'admin', status: 'active');
      const employee = EmployeeRecord(
        id: 'e2',
        role: 'employee',
        status: 'active',
      );
      const disabled = EmployeeRecord(
        id: 'e3',
        role: 'employee',
        status: 'disabled',
      );

      expect(admin.isAdmin, isTrue);
      expect(employee.isAdmin, isFalse);
      expect(admin.isActive, isTrue);
      expect(disabled.isActive, isFalse);
      expect(disabled.isDisabled, isTrue);
      expect(employee.isDisabled, isFalse);
    });

    test('initials returns first letter for one word', () {
      const e = EmployeeRecord(id: 'e1', name: 'Jane');
      expect(e.initials, 'J');
    });

    test('initials returns first letters of two words', () {
      const e = EmployeeRecord(id: 'e1', name: 'Jane Doe');
      expect(e.initials, 'JD');
    });

    test('initials returns ? for empty name', () {
      const e = EmployeeRecord(id: 'e1');
      expect(e.initials, '?');
    });

    test('toMap → fromMap roundtrip preserves data', () {
      const original = EmployeeRecord(
        id: 'e1',
        name: 'Jane Doe',
        email: 'jane@example.com',
        phone: '+1-514-555-0101',
        color: Color(0xFFEC4899),
        role: 'admin',
        status: 'active',
        uid: 'firebase-uid-1',
      );

      final restored = EmployeeRecord.fromMap(original.id, original.toMap());

      expect(restored, equals(original));
    });

    test('fromMap defaults missing fields to sensible empties', () {
      final r = EmployeeRecord.fromMap('e1', const {});
      expect(r.id, 'e1');
      expect(r.name, '');
      expect(r.role, 'employee');
      expect(r.status, '');
      expect(r.uid, '');
      // Default color is blue when colorValue is missing/unparseable.
      expect(r.color, isNotNull);
    });

    test('fromMap parses colorValue as decimal int string', () {
      final r = EmployeeRecord.fromMap('e1', const {'colorValue': '4280391411'});
      expect(r.color.toARGB32(), 4280391411);
    });
  });
}
