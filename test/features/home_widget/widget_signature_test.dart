import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/home_widget/application/widget_sync_service.dart';

void main() {
  group('WidgetSyncService.signatureForTesting', () {
    test('ignores generatedAt so the same jobs dedupe', () {
      final a = {
        'generatedAt': '2026-07-08T12:00:00Z',
        'jobs': [
          {'id': 'j1', 'clientName': 'Ada'},
        ],
      };
      final b = {
        'generatedAt': '2026-07-08T12:05:00Z',
        'jobs': [
          {'id': 'j1', 'clientName': 'Ada'},
        ],
      };

      expect(
        WidgetSyncService.signatureForTesting(a),
        WidgetSyncService.signatureForTesting(b),
      );
    });

    test('changed jobs produce a different signature', () {
      final a = {
        'generatedAt': '2026-07-08T12:00:00Z',
        'jobs': [
          {'id': 'j1', 'clientName': 'Ada'},
        ],
      };
      final b = {
        'generatedAt': '2026-07-08T12:00:00Z',
        'jobs': [
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
