import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/home_widget/application/widget_sync_service.dart';

class _RecordingLogger extends AppLogger {
  final warnings = <String>[];

  @override
  void warn(String message, [Object? error, StackTrace? stack]) {
    warnings.add(message);
  }
}

/// Records every App Group write, and can be made to fail on demand.
class _Writer {
  final calls = <String?>[];
  bool failNext = false;

  Future<void> call(String? payloadJson) async {
    calls.add(payloadJson);
    if (failNext) throw StateError('App Group write failed');
  }
}

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

  group('sync / clear', () {
    late _Writer writer;
    late _RecordingLogger logger;

    const payload = {
      'generatedAt': '2026-07-08T12:00:00Z',
      'todayJobs': [
        {'id': 'j1'},
      ],
    };

    WidgetSyncService service({bool isIos = true}) => WidgetSyncService(
      logger: logger,
      isIosPlatform: () => isIos,
      write: writer.call,
    );

    setUp(() {
      writer = _Writer();
      logger = _RecordingLogger();
    });

    test('writes the encoded payload into the App Group', () async {
      await service().sync(payload);

      expect(writer.calls, [jsonEncode(payload)]);
      expect(logger.warnings, isEmpty);
    });

    test('an unchanged schedule is not rewritten', () async {
      final s = service();
      await s.sync(payload);
      await s.sync({...payload, 'generatedAt': '2026-07-08T12:05:00Z'});

      // `generatedAt` moves on every rebuild, so the dedup has to ignore it or
      // it never fires at all.
      expect(writer.calls, hasLength(1));
    });

    test('a FAILED write is not remembered, so the next sync retries', () async {
      // The ordering that matters: `_lastState` is stamped only AFTER the
      // write lands. Stamp it first and a failed write is remembered as the
      // current state, so the next identical payload dedupes away and the
      // home screen is frozen on stale jobs until the schedule itself changes.
      final s = service();
      writer.failNext = true;
      await s.sync(payload);
      writer.failNext = false;
      await s.sync(payload);

      expect(writer.calls, hasLength(2));
      expect(logger.warnings.single, startsWith('WIDGET sync failed'));
    });

    test('clear wipes the key and then dedupes', () async {
      final s = service();
      await s.sync(payload);
      await s.clear();
      await s.clear();

      expect(writer.calls, [jsonEncode(payload), null]);
    });

    test('a FAILED clear is not remembered either', () async {
      // Same rule the other way: a signed-out user's jobs would otherwise sit
      // in the shared App Group until something else happened to write.
      final s = service();
      writer.failNext = true;
      await s.clear();
      writer.failNext = false;
      await s.clear();

      expect(writer.calls, [null, null]);
      expect(logger.warnings.single, startsWith('WIDGET clear failed'));
    });

    test('nothing is written off iOS', () async {
      final s = service(isIos: false);
      await s.sync(payload);
      await s.clear();

      expect(writer.calls, isEmpty);
    });
  });
}
