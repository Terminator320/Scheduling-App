import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';
import 'package:scheduling/features/employees/domain/policies/work_schedule_policy.dart';

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
        status: 'active',
      );
      const disabled = EmployeeRecord(
        id: 'e3',
        status: 'disabled',
      );

      expect(admin.isAdmin, isTrue);
      expect(employee.isAdmin, isFalse);
      expect(admin.isActive, isTrue);
      expect(disabled.isActive, isFalse);
      expect(disabled.isDisabled, isTrue);
      expect(employee.isDisabled, isFalse);
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
      final r = EmployeeRecord.fromMap('e1', const {
        'colorValue': '4280391411',
      });
      expect(r.color.toARGB32(), 4280391411);
    });
  });

  group('P4 fields', () {
    test('fromMap reads the new fields', () {
      final record = EmployeeRecord.fromMap('e1', {
        'name': 'Theo Roy',
        'firstName': 'Theo',
        'lastName': 'Roy',
        'jobTitle': 'lead_tech',
        'workingDays': [false, true, true, true, true, true, false],
        'workStartMinutes': 420,
        'workEndMinutes': 960,
        'maxJobsPerDay': 5,
        'onCall': true,
        'emergencyContact': 'Marie 555-0100',
      });

      expect(record.firstName, 'Theo');
      expect(record.jobTitle, JobTitle.leadTech);
      expect(record.workStartMinutes, 420);
      expect(record.maxJobsPerDay, 5);
      expect(record.onCall, isTrue);
      expect(record.emergencyContact, 'Marie 555-0100');
    });

    test('a legacy doc with none of them gets working defaults', () {
      final record = EmployeeRecord.fromMap('e1', {'name': 'Old User'});

      expect(record.firstName, '');
      expect(record.jobTitle, JobTitle.unset);
      expect(record.workingDays, kDefaultWorkingDays);
      expect(record.workStartMinutes, kDefaultWorkStartMinutes);
      expect(record.workEndMinutes, kDefaultWorkEndMinutes);
      expect(record.maxJobsPerDay, 0);
      expect(record.onCall, isFalse);
    });

    test('an unknown stored jobTitle falls back to unset', () {
      final record = EmployeeRecord.fromMap('e1', {
        'jobTitle': 'plumber-in-chief',
      });
      expect(record.jobTitle, JobTitle.unset);
    });

    test('a malformed workingDays list is normalized to seven flags', () {
      final record = EmployeeRecord.fromMap('e1', {
        'workingDays': [true, true],
      });
      expect(record.workingDays.length, 7);
      expect(record.workingDays[0], isTrue);
      expect(record.workingDays[6], isFalse);
    });

    test('toMap round-trips every editable field', () {
      const record = EmployeeRecord(
        id: 'e1',
        name: 'Theo Roy',
        firstName: 'Theo',
        lastName: 'Roy',
        jobTitle: JobTitle.dispatcher,
        maxJobsPerDay: 3,
        onCall: true,
        emergencyContact: 'Marie',
      );

      final restored = EmployeeRecord.fromMap('e1', record.toMap());

      expect(restored.firstName, 'Theo');
      expect(restored.jobTitle, JobTitle.dispatcher);
      expect(restored.maxJobsPerDay, 3);
      expect(restored.onCall, isTrue);
      expect(restored.emergencyContact, 'Marie');
    });
  });
}
