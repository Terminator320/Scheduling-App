import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/wave/data/wave_service.dart';
import 'package:scheduling/features/wave/domain/models/wave_connection.dart';
import 'package:scheduling/features/wave/domain/wave_error_mapper.dart';
import 'package:scheduling/features/wave/domain/wave_failure.dart';
import 'package:scheduling/l10n/l10n.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockCallable extends Mock implements HttpsCallable {}

class _MockResult extends Mock implements HttpsCallableResult<dynamic> {}

class _FakeHttpsCallableOptions extends Fake implements HttpsCallableOptions {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

FirebaseFunctionsException _fnEx(String code, String message) =>
    FirebaseFunctionsException(code: code, message: message);

// Pump a minimal app that provides l10n so widgets can resolve context.l10n.
Future<BuildContext> _pumpL10nContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (ctx) {
          captured = ctx;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

// ---------------------------------------------------------------------------
// WaveErrorMapper
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeHttpsCallableOptions());
  });

  group('WaveErrorMapper.map', () {
    test('passes through an existing WaveFailure unchanged', () {
      const failure = WaveAuthInvalid();
      expect(WaveErrorMapper.map(failure), same(failure));
    });

    test('wave/token-invalid → WaveAuthInvalid', () {
      expect(
        WaveErrorMapper.map(_fnEx('failed-precondition', 'wave/token-invalid')),
        isA<WaveAuthInvalid>(),
      );
    });

    test('wave/rate-limited message → WaveRateLimited', () {
      expect(
        WaveErrorMapper.map(_fnEx('failed-precondition', 'wave/rate-limited')),
        isA<WaveRateLimited>(),
      );
    });

    test('code resource-exhausted → WaveRateLimited', () {
      expect(
        WaveErrorMapper.map(_fnEx('resource-exhausted', 'some-message')),
        isA<WaveRateLimited>(),
      );
    });

    test('wave/network message → WaveNetwork', () {
      expect(
        WaveErrorMapper.map(_fnEx('unavailable', 'wave/network')),
        isA<WaveNetwork>(),
      );
    });

    test('code unavailable → WaveNetwork', () {
      expect(
        WaveErrorMapper.map(_fnEx('unavailable', 'other')),
        isA<WaveNetwork>(),
      );
    });

    test('wave/validation message → WaveValidation', () {
      expect(
        WaveErrorMapper.map(_fnEx('invalid-argument', 'wave/validation')),
        isA<WaveValidation>(),
      );
    });

    test('code invalid-argument → WaveValidation', () {
      expect(
        WaveErrorMapper.map(_fnEx('invalid-argument', 'something')),
        isA<WaveValidation>(),
      );
    });

    test('wave/not-bootstrapped → WaveValidation with precondition reason', () {
      final result = WaveErrorMapper.map(
        _fnEx('failed-precondition', 'wave/not-bootstrapped'),
      );
      expect(result, isA<WaveValidation>());
      expect((result as WaveValidation).reason, 'precondition');
    });

    test(
      'wave/business-ambiguous → WaveValidation with precondition reason',
      () {
        final result = WaveErrorMapper.map(
          _fnEx('failed-precondition', 'wave/business-ambiguous'),
        );
        expect(result, isA<WaveValidation>());
        expect((result as WaveValidation).reason, 'precondition');
      },
    );

    test(
      'wave/business-not-found → WaveValidation with precondition reason',
      () {
        final result = WaveErrorMapper.map(
          _fnEx('not-found', 'wave/business-not-found'),
        );
        expect(result, isA<WaveValidation>());
        expect((result as WaveValidation).reason, 'precondition');
      },
    );

    test('wave/not-admin → WaveUnknown', () {
      expect(
        WaveErrorMapper.map(_fnEx('permission-denied', 'wave/not-admin')),
        isA<WaveUnknown>(),
      );
    });

    test('wave/unknown message → WaveUnknown', () {
      expect(
        WaveErrorMapper.map(_fnEx('internal', 'wave/unknown')),
        isA<WaveUnknown>(),
      );
    });

    test('code internal → WaveUnknown', () {
      expect(
        WaveErrorMapper.map(_fnEx('internal', 'something')),
        isA<WaveUnknown>(),
      );
    });

    test('unknown error type → WaveUnknown', () {
      expect(
        WaveErrorMapper.map(Exception('unrelated')),
        isA<WaveUnknown>(),
      );
    });
  });

  // -------------------------------------------------------------------------
  // WaveConnection.fromMap
  // -------------------------------------------------------------------------

  group('WaveConnection.fromMap', () {
    test('parses businessId and businessName', () {
      final conn = WaveConnection.fromMap(const {
        'businessId': 'biz-1',
        'businessName': 'Acme Corp',
      });
      expect(conn.businessId, 'biz-1');
      expect(conn.businessName, 'Acme Corp');
    });

    test('defaults missing fields to empty string', () {
      final conn = WaveConnection.fromMap(const {});
      expect(conn.businessId, '');
      expect(conn.businessName, '');
    });
  });

  // -------------------------------------------------------------------------
  // WaveImportSummary.fromMap
  // -------------------------------------------------------------------------

  group('WaveImportSummary.fromMap', () {
    test('parses all numeric fields', () {
      final summary = WaveImportSummary.fromMap(const {
        'totalCount': 100,
        'imported': 80,
        'updated': 15,
        'skippedArchived': 5,
        'pages': 3,
      });
      expect(summary.totalCount, 100);
      expect(summary.imported, 80);
      expect(summary.updated, 15);
      expect(summary.skippedArchived, 5);
      expect(summary.pages, 3);
    });

    test('defaults missing fields to zero', () {
      final summary = WaveImportSummary.fromMap(const {});
      expect(summary.totalCount, 0);
      expect(summary.imported, 0);
      expect(summary.updated, 0);
      expect(summary.skippedArchived, 0);
      expect(summary.pages, 0);
    });
  });

  // -------------------------------------------------------------------------
  // WaveService
  // -------------------------------------------------------------------------

  group('WaveService', () {
    late _MockFunctions functions;
    late _MockCallable bootstrapCallable;
    late _MockCallable importCallable;
    late WaveService service;

    setUp(() {
      functions = _MockFunctions();
      bootstrapCallable = _MockCallable();
      importCallable = _MockCallable();
      when(
        () => functions.httpsCallable('waveBootstrap'),
      ).thenReturn(bootstrapCallable);
      when(
        () => functions.httpsCallable('waveImportCustomers'),
      ).thenReturn(importCallable);
      service = WaveService(functions: functions);
    });

    group('bootstrap', () {
      test('parses WaveConnection from callable result', () async {
        final result = _MockResult();
        when(() => result.data).thenReturn(<String, dynamic>{
          'businessId': 'biz-42',
          'businessName': 'Test Co',
        });
        when(
          () => bootstrapCallable.call<dynamic>(any<Object?>()),
        ).thenAnswer((_) async => result);

        final conn = await service.bootstrap();
        expect(conn.businessId, 'biz-42');
        expect(conn.businessName, 'Test Co');
      });

      test('sends businessId in payload when provided', () async {
        final result = _MockResult();
        when(() => result.data).thenReturn(<String, dynamic>{
          'businessId': 'biz-42',
          'businessName': 'Test Co',
        });
        when(
          () => bootstrapCallable.call<dynamic>(any<Object?>()),
        ).thenAnswer((_) async => result);

        await service.bootstrap(businessId: 'biz-42');

        final captured =
            verify(
                  () => bootstrapCallable.call<dynamic>(captureAny<Object?>()),
                ).captured.single
                as Map;
        expect(captured['businessId'], 'biz-42');
        expect(captured.containsKey('businessName'), isFalse);
      });

      test('sends businessName in payload when provided', () async {
        final result = _MockResult();
        when(() => result.data).thenReturn(<String, dynamic>{
          'businessId': 'biz-1',
          'businessName': 'Acme',
        });
        when(
          () => bootstrapCallable.call<dynamic>(any<Object?>()),
        ).thenAnswer((_) async => result);

        await service.bootstrap(businessName: 'Acme');

        final captured =
            verify(
                  () => bootstrapCallable.call<dynamic>(captureAny<Object?>()),
                ).captured.single
                as Map;
        expect(captured['businessName'], 'Acme');
        expect(captured.containsKey('businessId'), isFalse);
      });

      test(
        'FirebaseFunctionsException → mapped WaveFailure is thrown',
        () async {
          when(() => bootstrapCallable.call<dynamic>(any<Object?>())).thenThrow(
            _fnEx('resource-exhausted', 'wave/rate-limited'),
          );

          expect(
            () => service.bootstrap(),
            throwsA(isA<WaveRateLimited>()),
          );
        },
      );

      test(
        'FirebaseFunctionsException(wave/token-invalid) → WaveAuthInvalid',
        () async {
          when(() => bootstrapCallable.call<dynamic>(any<Object?>())).thenThrow(
            _fnEx('failed-precondition', 'wave/token-invalid'),
          );

          expect(
            () => service.bootstrap(),
            throwsA(isA<WaveAuthInvalid>()),
          );
        },
      );
    });

    group('importCustomers', () {
      test('parses WaveImportSummary from callable result', () async {
        final result = _MockResult();
        when(() => result.data).thenReturn(<String, dynamic>{
          'totalCount': 50,
          'imported': 30,
          'updated': 10,
          'skippedArchived': 10,
          'pages': 2,
        });
        when(
          () => importCallable.call<dynamic>(any<Object?>()),
        ).thenAnswer((_) async => result);

        final summary = await service.importCustomers();
        expect(summary.totalCount, 50);
        expect(summary.imported, 30);
        expect(summary.updated, 10);
        expect(summary.skippedArchived, 10);
        expect(summary.pages, 2);
      });

      test(
        'FirebaseFunctionsException → mapped WaveFailure is thrown',
        () async {
          when(() => importCallable.call<dynamic>(any<Object?>())).thenThrow(
            _fnEx('unavailable', 'wave/network'),
          );

          expect(
            () => service.importCustomers(),
            throwsA(isA<WaveNetwork>()),
          );
        },
      );

      test('FirebaseFunctionsException(internal) → WaveUnknown', () async {
        when(() => importCallable.call<dynamic>(any<Object?>())).thenThrow(
          _fnEx('internal', 'wave/unknown'),
        );

        expect(
          () => service.importCustomers(),
          throwsA(isA<WaveUnknown>()),
        );
      });
    });
  });

  // -------------------------------------------------------------------------
  // WaveFailure.toLocalizedMessage — light widget test
  // -------------------------------------------------------------------------

  group('WaveFailure.toLocalizedMessage', () {
    testWidgets('WaveAuthInvalid yields non-empty string', (tester) async {
      final ctx = await _pumpL10nContext(tester);
      expect(
        const WaveAuthInvalid().toLocalizedMessage(ctx),
        isNotEmpty,
      );
    });

    testWidgets('WaveRateLimited yields non-empty string', (tester) async {
      final ctx = await _pumpL10nContext(tester);
      expect(
        const WaveRateLimited().toLocalizedMessage(ctx),
        isNotEmpty,
      );
    });

    testWidgets('WaveValidation yields non-empty string', (tester) async {
      final ctx = await _pumpL10nContext(tester);
      expect(
        const WaveValidation().toLocalizedMessage(ctx),
        isNotEmpty,
      );
    });

    testWidgets('WaveNetwork yields non-empty string', (tester) async {
      final ctx = await _pumpL10nContext(tester);
      expect(
        const WaveNetwork().toLocalizedMessage(ctx),
        isNotEmpty,
      );
    });

    testWidgets('WaveUnknown yields non-empty string', (tester) async {
      final ctx = await _pumpL10nContext(tester);
      expect(
        const WaveUnknown().toLocalizedMessage(ctx),
        isNotEmpty,
      );
    });
  });
}
