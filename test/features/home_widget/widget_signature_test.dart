import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/home_widget/application/widget_sync_service.dart';

void main() {
  group('WidgetSyncService.signatureForTesting', () {
    test('ignores generatedAt so the same schedule dedupes', () {
      final a = {
        'generatedAt': '2026-07-08T12:00:00Z',
        'rolloverAt': null,
        'todayJobs': [
          {'id': 'j1', 'clientName': 'Ada'},
        ],
        'tomorrowJobs': const <Object>[],
      };
      final b = {
        'generatedAt': '2026-07-08T12:05:00Z',
        'rolloverAt': null,
        'todayJobs': [
          {'id': 'j1', 'clientName': 'Ada'},
        ],
        'tomorrowJobs': const <Object>[],
      };

      expect(
        WidgetSyncService.signatureForTesting(a),
        WidgetSyncService.signatureForTesting(b),
      );
    });

    test('a changed rollover instant produces a different signature', () {
      final a = {
        'generatedAt': '2026-07-08T12:00:00Z',
        'rolloverAt': null,
        'todayJobs': [
          {'id': 'j1', 'clientName': 'Ada'},
        ],
        'tomorrowJobs': const <Object>[],
      };
      final b = {
        'generatedAt': '2026-07-08T12:00:00Z',
        'rolloverAt': '2026-07-08T17:00:00Z',
        'todayJobs': const <Object>[],
        'tomorrowJobs': [
          {'id': 'j2', 'clientName': 'Grace'},
        ],
      };

      expect(
        WidgetSyncService.signatureForTesting(a),
        isNot(WidgetSyncService.signatureForTesting(b)),
      );
    });
  });
}
