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

    test('toMap → fromMap roundtrip preserves the editable fields', () {
      const original = EmployeeRecord(
        id: 'e1',
        name: 'Jane Doe',
        email: 'jane@example.com',
        phone: '+1-514-555-0101',
        color: Color(0xFFEC4899),
        role: 'admin',
      );

      final restored = EmployeeRecord.fromMap(original.id, original.toMap());

      expect(restored, equals(original));
    });

    test('toMap emits neither uid nor status — the repository owns both', () {
      const record = EmployeeRecord(
        id: 'e1',
        name: 'Jane Doe',
        status: 'active',
        uid: 'firebase-uid-1',
      );

      final map = record.toMap();

      // `uid` is on the /users update denylist in firestore.rules and `status`
      // belongs to deactivate/reactivate, so a whole-record write carrying
      // either comes back as an opaque permission-denied.
      expect(map.containsKey('uid'), isFalse);
      expect(map.containsKey('status'), isFalse);
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
      );

      final restored = EmployeeRecord.fromMap('e1', record.toMap());

      expect(restored.firstName, 'Theo');
      expect(restored.jobTitle, JobTitle.dispatcher);
      expect(restored.maxJobsPerDay, 3);
      expect(restored.onCall, isTrue);
    });
  });

  group('server-owned read-only fields', () {
    test('fromMap reads codeExpiresAt and createdAt', () {
      final expiry = DateTime(2026, 8, 16, 9, 30);
      final created = DateTime(2026, 8, 2, 14);
      final record = EmployeeRecord.fromMap('e1', {
        'name': 'Theo Roy',
        'status': 'invited',
        'codeExpiresAt': expiry,
        'createdAt': created,
      });

      expect(record.codeExpiresAt, expiry);
      expect(record.createdAt, created);
    });

    test('both are null when absent', () {
      final record = EmployeeRecord.fromMap('e1', const {'name': 'Theo'});

      expect(record.codeExpiresAt, isNull);
      expect(record.createdAt, isNull);
    });

    test('toMap emits neither — they are function-owned', () {
      final record = EmployeeRecord(
        id: 'e1',
        name: 'Theo Roy',
        codeExpiresAt: DateTime(2026, 8, 16),
        createdAt: DateTime(2026, 8, 2),
      );

      final map = record.toMap();

      // firestore.rules rejects any client update whose diff touches
      // codeExpiresAt, so emitting it would make a whole-record write a
      // permission-denied grenade.
      expect(map.containsKey('codeExpiresAt'), isFalse);
      expect(map.containsKey('createdAt'), isFalse);
    });

    test('a toMap round-trip drops them rather than corrupting them', () {
      final record = EmployeeRecord(
        id: 'e1',
        name: 'Theo Roy',
        codeExpiresAt: DateTime(2026, 8, 16),
        createdAt: DateTime(2026, 8, 2),
      );

      final restored = EmployeeRecord.fromMap('e1', record.toMap());

      expect(restored.codeExpiresAt, isNull);
      expect(restored.createdAt, isNull);
    });
  });
}
