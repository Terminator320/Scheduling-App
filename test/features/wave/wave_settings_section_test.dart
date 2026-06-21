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
    testWidgets('shows Connect and Import buttons', (tester) async {
      final service = _MockWaveService();
      await tester.pumpWidget(_wrapSection(service));
      await tester.pumpAndSettle();

      expect(find.text('Connect to Wave'), findsOneWidget);
      expect(find.text('Import customers from Wave'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Import button is disabled before Connect succeeds', (
      tester,
    ) async {
      final service = _MockWaveService();
      await tester.pumpWidget(_wrapSection(service));
      await tester.pumpAndSettle();

      // Tap Import — the button has no onPressed when not connected, so
      // nothing should happen (no call on the service).
      await tester.tap(find.text('Import customers from Wave'));
      await tester.pump();

      verifyNever(service.importCustomers);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Connect success shows business name and success notice', (
      tester,
    ) async {
      final service = _MockWaveService();
      final notices = NoticeService();
      final emitted = <String>[];
      notices.stream.listen((n) => emitted.add(n.message));

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

      // Business name appears in the connected-state indicator.
      expect(find.text('Acme Corp'), findsOneWidget);
      // Success notice was emitted.
      expect(emitted, anyElement(contains('Acme Corp')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Connect failure surfaces an error notice', (tester) async {
      final service = _MockWaveService();
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
      // Business name is NOT shown (connection was not established).
      expect(find.text('Acme Corp'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Import success after Connect shows success notice', (
      tester,
    ) async {
      final service = _MockWaveService();
      final notices = NoticeService();
      final emitted = <String>[];
      notices.stream.listen((n) => emitted.add(n.message));

      when(service.bootstrap).thenAnswer(
        (_) async => const WaveConnection(
          businessId: 'biz-1',
          businessName: 'Test Biz',
        ),
      );
      when(service.importCustomers).thenAnswer(
        (_) async => const WaveImportSummary(
          totalCount: 10,
          imported: 8,
          updated: 2,
          skippedArchived: 0,
          pages: 1,
        ),
      );

      await tester.pumpWidget(_wrapSection(service, noticeService: notices));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect to Wave'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Import customers from Wave'));
      await tester.pumpAndSettle();

      // Import success notice contains the counts.
      expect(emitted.last, contains('8'));
      expect(emitted.last, contains('2'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Import failure surfaces an error notice', (tester) async {
      final service = _MockWaveService();
      final notices = NoticeService();
      final emitted = <AppNotice>[];
      notices.stream.listen(emitted.add);

      when(service.bootstrap).thenAnswer(
        (_) async => const WaveConnection(
          businessId: 'biz-1',
          businessName: 'Test Biz',
        ),
      );
      when(service.importCustomers).thenThrow(const WaveAuthInvalid());

      await tester.pumpWidget(_wrapSection(service, noticeService: notices));
      await tester.pumpAndSettle();

      // Connect first so the Import button is enabled.
      await tester.tap(find.text('Connect to Wave'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Import customers from Wave'));
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

      await tester.pumpWidget(_wrapSettings(role: 'admin'));
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
