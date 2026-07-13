import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/wave/data/wave_service.dart';
import 'package:scheduling/features/wave/domain/models/wave_import_schedule.dart';
import 'package:scheduling/features/wave/domain/wave_failure.dart';

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockCallable extends Mock implements HttpsCallable {}

class _MockResult extends Mock implements HttpsCallableResult<dynamic> {}

class _FakeHttpsCallableOptions extends Fake implements HttpsCallableOptions {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeHttpsCallableOptions()));

  late _MockFunctions functions;
  late _MockCallable callable;
  late WaveService service;

  void bind(String name) {
    when(
      () => functions.httpsCallable(
        any(that: equals(name)),
        options: any(named: 'options'),
      ),
    ).thenReturn(callable);
  }

  setUp(() {
    functions = _MockFunctions();
    callable = _MockCallable();
    service = WaveService(functions: functions);
  });

  group('bootstrap', () {
    test('parses the connection payload', () async {
      bind('waveBootstrap');
      final result = _MockResult();
      when(() => result.data).thenReturn(<String, dynamic>{
        'businessId': 'biz-1',
        'businessName': 'Acme Plumbing',
        'importSchedule': 'weekly',
      });
      when(
        () => callable.call<dynamic>(any<Object?>()),
      ).thenAnswer((_) async => result);

      final conn = await service.bootstrap();

      expect(conn.businessId, 'biz-1');
      expect(conn.businessName, 'Acme Plumbing');
      expect(conn.importSchedule, WaveImportSchedule.weekly);
    });

    test(
      'tolerates an Android Map<dynamic, dynamic> callable payload',
      () async {
        bind('waveBootstrap');
        final result = _MockResult();
        // Android callables hand back Map<dynamic, dynamic>, not
        // Map<String, dynamic> — the loose cast must survive it.
        when(() => result.data).thenReturn(<dynamic, dynamic>{
          'businessId': 'biz-2',
          'businessName': 'Beta Co',
        });
        when(
          () => callable.call<dynamic>(any<Object?>()),
        ).thenAnswer((_) async => result);

        final conn = await service.bootstrap();

        expect(conn.businessId, 'biz-2');
        expect(conn.importSchedule, WaveImportSchedule.off);
      },
    );

    test('maps a callable failure to a WaveFailure', () async {
      bind('waveBootstrap');
      when(
        () => callable.call<dynamic>(any<Object?>()),
      ).thenThrow(Exception('boom'));

      await expectLater(service.bootstrap(), throwsA(isA<WaveFailure>()));
    });
  });

  group('getConnection', () {
    test('returns null when the payload is not connected', () async {
      bind('waveGetConnection');
      final result = _MockResult();
      when(() => result.data).thenReturn(<String, dynamic>{'connected': false});
      when(
        () => callable.call<dynamic>(any<Object?>()),
      ).thenAnswer((_) async => result);

      expect(await service.getConnection(), isNull);
    });

    test('parses a connected payload', () async {
      bind('waveGetConnection');
      final result = _MockResult();
      when(() => result.data).thenReturn(<String, dynamic>{
        'connected': true,
        'businessId': 'biz-9',
        'businessName': 'Gamma Ltd',
        'importSchedule': 'monthly',
      });
      when(
        () => callable.call<dynamic>(any<Object?>()),
      ).thenAnswer((_) async => result);

      final conn = await service.getConnection();

      expect(conn, isNotNull);
      expect(conn!.businessId, 'biz-9');
      expect(conn.importSchedule, WaveImportSchedule.monthly);
    });
  });

  group('importCustomers', () {
    test('parses the import summary', () async {
      bind('waveImportCustomers');
      final result = _MockResult();
      when(() => result.data).thenReturn(<String, dynamic>{
        'totalCount': 10,
        'imported': 7,
        'updated': 2,
        'skippedArchived': 1,
        'pages': 3,
      });
      when(
        () => callable.call<dynamic>(any<Object?>()),
      ).thenAnswer((_) async => result);

      final summary = await service.importCustomers();

      expect(summary.totalCount, 10);
      expect(summary.imported, 7);
      expect(summary.updated, 2);
      expect(summary.skippedArchived, 1);
      expect(summary.pages, 3);
    });
  });

  group('setImportSchedule', () {
    test('sends schedule.raw and completes on success', () async {
      bind('waveSetImportSchedule');
      when(
        () => callable.call<void>(any<Object?>()),
      ).thenAnswer((_) async => _MockResult());

      await service.setImportSchedule(WaveImportSchedule.weekly);

      final captured = verify(
        () => callable.call<void>(captureAny<Object?>()),
      ).captured.single;
      final payload = (captured as Map).cast<String, dynamic>();
      expect(payload['schedule'], 'weekly');
    });

    test('maps a callable failure to a WaveFailure', () async {
      bind('waveSetImportSchedule');
      when(
        () => callable.call<void>(any<Object?>()),
      ).thenThrow(Exception('nope'));

      await expectLater(
        service.setImportSchedule(WaveImportSchedule.off),
        throwsA(isA<WaveFailure>()),
      );
    });
  });
}
