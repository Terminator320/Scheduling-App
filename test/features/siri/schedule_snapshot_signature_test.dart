import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/siri/application/schedule_snapshot_service.dart';

void main() {
  group('ScheduleSnapshotService.signatureForTesting', () {
    test('ignores generatedAt so an unchanged schedule dedupes', () {
      final a = {
        'version': 1,
        'generatedAt': 1791234567890,
        'role': 'employee',
        'days': [
          {
            'date': '2026-07-19',
            'appointments': [
              {'id': 'j1', 'clientName': 'Ada'},
            ],
          },
        ],
      };
      final b = {...a, 'generatedAt': 1791234599999};

      expect(
        ScheduleSnapshotService.signatureForTesting(a),
        ScheduleSnapshotService.signatureForTesting(b),
      );
    });

    test('a changed schedule produces a different signature', () {
      final a = {
        'version': 1,
        'generatedAt': 1791234567890,
        'role': 'employee',
        'days': [
          {
            'date': '2026-07-19',
            'appointments': [
              {'id': 'j1', 'clientName': 'Ada'},
            ],
          },
        ],
      };
      final b = {
        ...a,
        'days': [
          {
            'date': '2026-07-19',
            'appointments': [
              {'id': 'j2', 'clientName': 'Grace'},
            ],
          },
        ],
      };

      expect(
        ScheduleSnapshotService.signatureForTesting(a),
        isNot(ScheduleSnapshotService.signatureForTesting(b)),
      );
    });

    test('a role change produces a different signature', () {
      final a = {
        'version': 1,
        'generatedAt': 1791234567890,
        'role': 'employee',
        'days': const <Object>[],
      };
      final b = {...a, 'role': 'admin'};

      expect(
        ScheduleSnapshotService.signatureForTesting(a),
        isNot(ScheduleSnapshotService.signatureForTesting(b)),
      );
    });
  });
}
