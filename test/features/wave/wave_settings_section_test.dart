import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:scheduling/core/notices/app_notice.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/settings/screens/settings_screen.dart';
import 'package:scheduling/features/wave/application/wave_providers.dart';
import 'package:scheduling/features/wave/data/wave_service.dart';
import 'package:scheduling/features/wave/domain/models/wave_connection.dart';
import 'package:scheduling/features/wave/domain/models/wave_import_schedule.dart';
import 'package:scheduling/features/wave/domain/wave_failure.dart';
import 'package:scheduling/features/wave/widgets/wave_settings_section.dart';
import 'package:scheduling/l10n/l10n.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class _MockWaveService extends Mock implements WaveService {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Mock service defaulting to not-connected; re-stub [WaveService.getConnection] for a connected state.
_MockWaveService _mockService() {
  final service = _MockWaveService();
  when(service.getConnection).thenAnswer((_) async => null);
  return service;
}

Widget _wrapSection(
  WaveService service, {
  NoticeService? noticeService,
}) {
  final notices = noticeService ?? NoticeService();
  return ProviderScope(
    overrides: [
      waveServiceProvider.overrideWithValue(service),
      noticeServiceProvider.overrideWithValue(notices),
    ],
    child: ThemeNotifier(
      themeMode: ThemeMode.light,
      toggleTheme: () {},
      textScale: 1,
      setTextScale: (_) {},
      setLanguage: (_) {},
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: lightTheme(),
        home: const Scaffold(
          body: SingleChildScrollView(child: WaveSettingsSection()),
        ),
      ),
    ),
  );
}

/// Wraps the full SettingsScreen for admin-gating tests.
Widget _wrapSettings({required String? role, WaveService? service}) {
  return ProviderScope(
    overrides: [
      if (service != null) waveServiceProvider.overrideWithValue(service),
    ],
    child: ThemeNotifier(
      themeMode: ThemeMode.light,
      toggleTheme: () {},
      textScale: 1,
      setTextScale: (_) {},
      setLanguage: (_) {},
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: lightTheme(),
        home: SettingsScreen(
          name: 'Test User',
          email: 'test@example.com',
          role: role,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(WaveImportSchedule.off);
    PackageInfo.setMockInitialValues(
      appName: 'Scheduling',
      packageName: 'net.vogas.scheduling',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  // ── WaveSettingsSection widget ────────────────────────────────────────────

  group('WaveSettingsSection', () {
    testWidgets('shows Connect and hides Import when not connected', (
      tester,
    ) async {
      final service = _mockService();
      await tester.pumpWidget(_wrapSection(service));
      await tester.pumpAndSettle();

      expect(find.text('Connect to Wave'), findsOneWidget);
      // Import is gated on a live connection — a tap while disconnected is
      // guaranteed to fail, so it isn't offered until Connect succeeds.
      expect(find.text('Sync with Wave'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows persisted connected business on mount', (tester) async {
      final service = _mockService();
      // Server reports an already-connected business — no Connect tap needed.
      when(service.getConnection).thenAnswer(
        (_) async => const WaveConnection(
          businessId: 'biz-1',
          businessName: 'Persisted Co',
        ),
      );

      await tester.pumpWidget(_wrapSection(service));
      await tester.pumpAndSettle();

      verify(service.getConnection).called(1);
      expect(find.text('Persisted Co'), findsOneWidget);
      // Connect is hidden once connected; only Import remains.
      expect(find.text('Connect to Wave'), findsNothing);
      expect(find.text('Sync with Wave'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sync is not offered before connecting', (tester) async {
      final service = _mockService();

      await tester.pumpWidget(_wrapSection(service));
      await tester.pumpAndSettle();

      // Sync only appears once connected, so a disconnected admin can't
      // trigger a guaranteed-to-fail sync in the first place.
      expect(find.text('Sync with Wave'), findsNothing);
      verifyNever(service.syncCustomers);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Connect bootstraps without showing a picker', (
      tester,
    ) async {
      final service = _mockService();
      final notices = NoticeService();
      final emitted = <String>[];
      notices.stream.listen((n) => emitted.add(n.message));

      // The target business is resolved server-side; the client passes nothing.
      when(service.bootstrap).thenAnswer(
        (_) async => const WaveConnection(
          businessId: 'biz-1',
          businessName: 'Acme Corp',
        ),
      );

      await tester.pumpWidget(_wrapSection(service, noticeService: notices));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect to Wave'));
      await tester.pumpAndSettle();

      // Bootstrap was called with no client-side business selector.
      verify(service.bootstrap).called(1);
      // Business name (from the server response) shows in the connected row.
      expect(find.text('Acme Corp'), findsOneWidget);
      // Success notice was emitted.
      expect(emitted, anyElement(contains('Acme Corp')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Connect with a blank business stays not-connected', (
      tester,
    ) async {
      final service = _mockService();
      final notices = NoticeService();
      final emitted = <AppNotice>[];
      notices.stream.listen(emitted.add);

      // Server resolved no business (e.g. misconfigured WAVE_BUSINESS_NAME).
      when(service.bootstrap).thenAnswer(
        (_) async => const WaveConnection(businessId: '', businessName: ''),
      );

      await tester.pumpWidget(_wrapSection(service, noticeService: notices));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect to Wave'));
      await tester.pumpAndSettle();

      // No flip to a blank "connected" state — Connect remains visible and an
      // error notice is surfaced.
      expect(find.text('Connect to Wave'), findsOneWidget);
      expect(emitted.last, isA<NoticeError>());
      expect(tester.takeException(), isNull);
    });

    testWidgets('Connect failure surfaces an error notice', (tester) async {
      final service = _mockService();
      final notices = NoticeService();
      final emitted = <String>[];
      notices.stream.listen((n) => emitted.add(n.message));

      when(service.bootstrap).thenThrow(const WaveAuthInvalid());

      await tester.pumpWidget(_wrapSection(service, noticeService: notices));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect to Wave'));
      await tester.pumpAndSettle();

      // An error notice is emitted (exact text from WaveAuthInvalid l10n key).
      expect(emitted, isNotEmpty);
      // No business name shown (connection was not established).
      expect(find.text('Acme Corp'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sync success after Connect names both directions', (
      tester,
    ) async {
      final service = _mockService();
      final notices = NoticeService();
      final emitted = <String>[];
      notices.stream.listen((n) => emitted.add(n.message));

      when(service.bootstrap).thenAnswer(
        (_) async => const WaveConnection(
          businessId: 'biz-1',
          businessName: 'Test Biz',
        ),
      );
      when(service.syncCustomers).thenAnswer(
        (_) async => const WaveSyncSummary(
          totalCount: 10,
          imported: 8,
          updated: 2,
          skippedArchived: 0,
          pages: 1,
          pushedCreated: 3,
          pushedUpdated: 1,
          pushedPending: 0,
          pushedFailed: 0,
          pushIncomplete: false,
        ),
      );

      await tester.pumpWidget(_wrapSection(service, noticeService: notices));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect to Wave'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sync with Wave'));
      await tester.pumpAndSettle();

      // The exact sentence is pinned by wave_sync_notice_test; here we only
      // check the button routes the summary through that composer, so a copy
      // tweak breaks one test instead of two.
      expect(emitted.last, contains('added to Wave'));
      expect(emitted.last, contains('added to the app'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking a cadence calls setImportSchedule and notices', (
      tester,
    ) async {
      final service = _mockService();
      final notices = NoticeService();
      final emitted = <String>[];
      notices.stream.listen((n) => emitted.add(n.message));

      when(service.getConnection).thenAnswer(
        (_) async => const WaveConnection(
          businessId: 'biz-1',
          businessName: 'Test Biz',
        ),
      );
      when(() => service.setImportSchedule(any())).thenAnswer((_) async {});

      await tester.pumpWidget(_wrapSection(service, noticeService: notices));
      await tester.pumpAndSettle();

      // Open the cadence picker (row shows the current 'Off' value).
      await tester.tap(find.text('Automatic import'));
      await tester.pumpAndSettle();

      // Choose Weekly from the sheet.
      await tester.tap(find.text('Weekly').last);
      await tester.pumpAndSettle();

      verify(
        () => service.setImportSchedule(WaveImportSchedule.weekly),
      ).called(1);
      expect(emitted.last, contains('Automatic import updated'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Import failure surfaces an error notice', (tester) async {
      final service = _mockService();
      final notices = NoticeService();
      final emitted = <AppNotice>[];
      notices.stream.listen(emitted.add);

      // Connect first so Import is offered, then make the import fail.
      when(service.bootstrap).thenAnswer(
        (_) async => const WaveConnection(
          businessId: 'biz-1',
          businessName: 'Test Biz',
        ),
      );
      when(service.syncCustomers).thenThrow(const WaveAuthInvalid());

      await tester.pumpWidget(_wrapSection(service, noticeService: notices));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect to Wave'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sync with Wave'));
      await tester.pumpAndSettle();

      // The last notice must be an error (import failed), never a success.
      expect(emitted, isNotEmpty);
      expect(emitted.last, isA<NoticeError>());
      expect(tester.takeException(), isNull);
    });
  });

  // ── Admin-gating in SettingsScreen ───────────────────────────────────────

  group('SettingsScreen Wave section admin gating', () {
    testWidgets('Wave section is visible for admin role', (tester) async {
      // Use a tall viewport so all settings sections are laid out.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // The section reads connection status on mount, so supply a stubbed
      // service (the default real provider would hit Firebase Functions).
      await tester.pumpWidget(
        _wrapSettings(role: 'admin', service: _mockService()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('INTEGRATIONS'), findsOneWidget);
      expect(find.text('Connect to Wave'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Wave section is hidden for employee role', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrapSettings(role: 'employee'));
      await tester.pumpAndSettle();

      expect(find.textContaining('INTEGRATIONS'), findsNothing);
      expect(find.text('Connect to Wave'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Wave section is hidden when role is null', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrapSettings(role: null));
      await tester.pumpAndSettle();

      expect(find.textContaining('INTEGRATIONS'), findsNothing);
      expect(find.text('Connect to Wave'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
