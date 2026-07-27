import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/core/adaptive/app_scroll_behavior.dart';
import 'package:scheduling/core/app/app_sync_listeners.dart';
import 'package:scheduling/core/connectivity/offline_banner.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/logging/unhandled_error_severity.dart';
import 'package:scheduling/core/notices/notice_listener.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/notifications/fcm_background_handler.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/core/security/app_lock.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/core/utils/retry.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/home_widget/application/widget_sync_service.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/onboarding/screens/onboarding_gate.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';
import 'package:scheduling/features/settings/application/settings_providers.dart';
import 'package:scheduling/features/settings/data/shared_prefs_settings_repository.dart';
import 'package:scheduling/features/settings/domain/models/app_settings.dart';
import 'package:scheduling/firebase_options.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/routes/hub_shell.dart';
import 'package:scheduling/shared/widgets/feedback/error_snack_bar.dart';

const bool _useFirebaseEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');
const String _emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);

Future<void> _wireFirebaseEmulator() async {
  FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
  FirebaseFunctions.instance.useFunctionsEmulator(_emulatorHost, 5001);
  await Future.wait<void>([
    FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099),
    FirebaseStorage.instance.useStorageEmulator(_emulatorHost, 9199),
  ]);
}

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
      // Inter is bundled (assets/fonts/) — never fetch fonts from the CDN.
      GoogleFonts.config.allowRuntimeFetching = false;
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

      final settingsFuture = SharedPrefsSettingsRepository().load();

      // Load env before Firebase. The locale inits run concurrently alongside
      // it so we're not blocked waiting.
      await dotenv.load(fileName: 'dev/.env');

      await Future.wait([
        Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ),
        initializeDateFormatting('en_CA'),
        initializeDateFormatting('fr_CA'),
      ]);

      // Pin offline cache before first Firestore read (SplashScreen).
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
      );

      // iOS widget refresh on background push — must register before runApp.
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      Future<void> firebaseReady;
      if (_useFirebaseEmulator) {
        await _wireFirebaseEmulator();
        firebaseReady = Future<void>.value();
      } else {
        // Wire error handlers synchronously before activation futures.
        final crashlytics = FirebaseCrashlytics.instance;
        FlutterError.onError = crashlytics.recordFlutterFatalError;
        PlatformDispatcher.instance.onError = (error, stack) {
          crashlytics.recordError(
            error,
            stack,
            fatal: isFatalUnhandledError(error),
          );
          return true;
        };

        // Not awaited — failures observed via firebaseReadyProvider.
        firebaseReady = Future.wait([
          crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode),
          FirebaseAppCheck.instance.activate(
            providerAndroid: kDebugMode
                ? const AndroidDebugProvider()
                : const AndroidPlayIntegrityProvider(),
            providerApple: kDebugMode
                ? const AppleDebugProvider()
                : const AppleAppAttestProvider(),
          ),
        ]);
      }

      final settings = await settingsFuture;

      runApp(
        ProviderScope(
          retry: (retryCount, error) => null,
          overrides: [
            firebaseReadyProvider.overrideWith((ref) => firebaseReady),
          ],
          child: PaulApp(settings: settings),
        ),
      );
    },
    (error, stack) {
      FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: isFatalUnhandledError(error),
      );
    },
  );
}

class PaulApp extends ConsumerStatefulWidget {
  const PaulApp({required this.settings, super.key});

  final AppSettings settings;

  @override
  ConsumerState<PaulApp> createState() => _PaulAppState();
}

class _PaulAppState extends ConsumerState<PaulApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _settingsRepository = SharedPrefsSettingsRepository();
  final _settingsSaveDebouncer = SettingsSaveDebouncer();
  late ThemeMode _themeMode;
  late double _textScale;
  late AppLanguageController _languageController;
  bool _isHandlingAccountExit = false;
  bool _controllerSyncsPrimed = false;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.settings.themeMode;
    _textScale = widget.settings.textScale;
    _languageController = AppLanguageController.instance;
    _languageController.setLanguage(widget.settings.language);
    _setupPushTapHandling();
    _setupWidgetTapHandling();
  }

  /// iOS home-widget taps deep-link to appointment detail via URI scheme.
  void _setupWidgetTapHandling() {
    if (!Platform.isIOS) return;
    // Register App Group before first widget read.
    unawaited(() async {
      try {
        await HomeWidget.setAppGroupId(widgetAppGroupId);
        HomeWidget.widgetClicked.listen(
          _handleWidgetTap,
          onError: (Object e, StackTrace st) =>
              ref.read(loggerProvider).warn('WIDGET-TAP stream error', e, st),
        );
        final launchUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
        await _handleWidgetTap(launchUri);
      } catch (e, st) {
        ref.read(loggerProvider).warn('WIDGET-TAP setup failed', e, st);
      }
    }());
  }

  Future<void> _handleWidgetTap(Uri? uri) async {
    if (uri == null) return;
    final appointmentId = uri.queryParameters['id']?.trim() ?? '';
    // Swallow errors to prevent leaking into zone handlers as FATAL crashes.
    try {
      await _openAppointmentDeepLink(appointmentId);
    } catch (e, st) {
      ref.read(loggerProvider).warn('WIDGET-TAP open failed', e, st);
    }
  }

  /// Notification taps open appointment detail on calendar hub.
  void _setupPushTapHandling() {
    final service = ref.read(pushNotificationServiceProvider);
    unawaited(
      service
          .initialMessage()
          .then(_handlePushTap)
          .catchError(
            (Object e, StackTrace st) => ref
                .read(loggerProvider)
                .warn('PUSH-TAP initial message failed', e, st),
          ),
    );
    service.onMessageOpenedApp.listen(
      _handlePushTap,
      onError: (Object e, StackTrace st) =>
          ref.read(loggerProvider).warn('PUSH-TAP stream error', e, st),
    );
  }

  Future<void> _handlePushTap(RemoteMessage? message) async {
    if (message == null) return;
    final appointmentId =
        (message.data['appointmentId'] as String?)?.trim() ?? '';
    // Swallow errors to prevent leaking into zone handlers as FATAL crashes.
    try {
      await _openAppointmentDeepLink(appointmentId);
    } catch (e, st) {
      ref.read(loggerProvider).warn('PUSH-TAP open failed', e, st);
    }
  }

  /// Shared deep-link handler — shows the calendar, then opens the
  /// appointment if it's valid.
  Future<void> _openAppointmentDeepLink(String appointmentId) async {
    if (FirebaseAuth.instance.currentUser == null) return;

    // Fetch this concurrently with hub startup. One retry is enough to
    // survive the auth-token race that can happen right after cold start.
    final recordFuture = appointmentId.isEmpty
        ? Future<AppointmentRecord?>.value()
        : retryAsync<AppointmentRecord?>(
            () => ref
                .read(appointmentsRepositoryProvider)
                .getAppointmentById(appointmentId),
            delays: const [Duration(milliseconds: 600)],
          ).catchError((Object e, StackTrace st) {
            ref
                .read(loggerProvider)
                .warn('PUSH-TAP load appointment failed', e, st);
            return null;
          });

    // Wait for hub on terminated-launch cold start.
    final shell = await _awaitLiveHub();
    if (shell == null || !mounted) return;
    shell.showCalendar();

    final record = await recordFuture;
    if (!mounted) return;

    final navContext = _navigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;
    // Collapse stacked routes to open appointment over calendar root.
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);

    if (appointmentId.isEmpty) return;
    if (record == null) {
      ref
          .read(noticeServiceProvider)
          .info(
            AppLocalizations.of(navContext).calendar_appointmentUnavailable,
          );
      return;
    }
    await showEventDetails(navContext, record, showActions: shell.isAdmin);
  }

  /// Polls for up to ~10s waiting for the live hub to appear. Returns null
  /// if it never shows up.
  Future<HubShellState?> _awaitLiveHub() async {
    for (var i = 0; i < 50; i++) {
      final shell = HubShell.liveState;
      if (shell != null && shell.mounted) return shell;
      if (!mounted) return null;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return null;
  }

  @override
  void dispose() {
    _settingsSaveDebouncer.dispose();
    super.dispose();
  }

  void toggleTheme() {
    // Resolve the default `system` mode against the live OS brightness first,
    // then flip that — so one tap always changes the appearance, instead of
    // needing two taps on a dark phone.
    final platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    setState(() {
      _themeMode = toggledThemeMode(_themeMode, platformBrightness);
    });
    _settingsRepository.save(themeMode: _themeMode);
  }

  void setTextScale(double value) {
    setState(() {
      _textScale = value;
    });
    _settingsSaveDebouncer.run(
      () => _settingsRepository.save(textScale: value),
    );
  }

  void setLanguage(String code) {
    _languageController.setLanguage(code);
    _settingsRepository.save(language: code);
    // Re-upsert the token so its `locale` field follows the app language.
    unawaited(ref.read(pushRegistrationControllerProvider).sync());
    // Same for the Live Activity tokens — `locale` drives the card's text.
    unawaited(ref.read(liveActivityRegistrationControllerProvider).sync());
    // The iOS home widget localizes its chrome/status labels from the
    // payload's `locale`. Recompute the payload now so the widget follows
    // the app language right away, instead of waiting for the next
    // appointment-stream emission.
    ref.invalidate(widgetPayloadProvider);
  }

  Future<void> _handleAccountDisabled(
    String Function(AppLocalizations) selectMessage,
  ) async {
    if (_isHandlingAccountExit) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    _isHandlingAccountExit = true;

    var exitScheduled = false;
    try {
      final message = selectMessage(AppLocalizations.of(navContext));
      // Best-effort de-registration first — a failure here shouldn't block sign-out.
      await ref
          .read(pushRegistrationControllerProvider)
          .unregisterCurrentDevice();
      await ref.read(presenceSyncControllerProvider).unregister();
      await ref.read(liveActivityRegistrationControllerProvider).unregister();
      await ref.read(authServiceProvider).signOut();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.pushNamedAndRemoveUntil(
          AppRoutes.login,
          (_) => false,
        );
        _scaffoldMessengerKey.currentState?.showSnackBar(
          errorSnackBar(navContext, message),
        );
        _isHandlingAccountExit = false;
      });
      exitScheduled = true;
    } catch (e, st) {
      // Sign-out failed — next signal retries.
      ref.read(loggerProvider).warn('ACCOUNT-EXIT sign-out failed', e, st);
    } finally {
      // Reset on failure to allow retry on next signal.
      if (!exitScheduled) _isHandlingAccountExit = false;
    }
  }

  void _listenForAccountDisabled() {
    ref.listen<AsyncValue<bool>>(accountDisabledProvider, (prev, next) {
      final wasDisabled = prev?.value ?? false;
      final isDisabled = next.value ?? false;
      if (!wasDisabled && isDisabled) {
        _handleAccountDisabled((l10n) => l10n.error_thisAccountHasBeenDisabled);
      }
    });
  }

  /// Syncs once on first build, in case the account doc is already present —
  /// harmless if it's not ready yet.
  void _primeControllerSyncsOnce() {
    if (_controllerSyncsPrimed) return;
    _controllerSyncsPrimed = true;
    unawaited(ref.read(pushRegistrationControllerProvider).sync());
    unawaited(ref.read(presenceSyncControllerProvider).sync());
    unawaited(ref.read(liveActivityRegistrationControllerProvider).sync());
  }

  void _listenForRoleRevocation() {
    ref.listen<AsyncValue<String>>(userRoleProvider, (prev, next) {
      final prevRole = prev?.value;
      final nextRole = next.value;
      // An empty role means deletion, not demotion — let
      // _listenForDeletedAccount handle that case.
      if (prevRole == 'admin' &&
          nextRole != null &&
          nextRole != '' &&
          nextRole != 'admin') {
        _handleAccountDisabled((l10n) => l10n.error_yourAdminAccessWasRevoked);
      }
    });
  }

  void _listenForDeletedAccount() {
    ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
      prev,
      next,
    ) {
      final isSignedIn = FirebaseAuth.instance.currentUser != null;
      final resolvedUid = ref.read(authUidProvider).value;
      // Kick the user out on a populated→empty transition. Cold-start
      // deletion is handled separately, below.
      if (isAccountDeletionSignal(
        isSignedIn: isSignedIn,
        resolvedUid: resolvedUid,
        previous: prev,
        docState: next,
      )) {
        _handleAccountDisabled((l10n) => l10n.error_thisAccountHasBeenDisabled);
        return;
      }
      unawaited(
        confirmColdStartDeletion(
          isSignedIn: isSignedIn,
          resolvedUid: resolvedUid,
          previous: prev,
          docState: next,
          loadWarmCache: ref.read(authCacheProvider).loadIfMatch,
          logger: ref.read(loggerProvider),
        ).then((deleted) {
          if (deleted && mounted) {
            _handleAccountDisabled(
              (l10n) => l10n.error_thisAccountHasBeenDisabled,
            );
          }
        }),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _listenForAccountDisabled();
    _listenForRoleRevocation();
    _listenForDeletedAccount();
    // Register the sync listeners — the order here matters for
    // account-lifecycle control, so don't reorder these calls.
    AppSyncListeners(ref).registerAll();
    _primeControllerSyncsOnce();
    return AppLanguageScope(
      controller: _languageController,
      child: ThemeNotifier(
        themeMode: _themeMode,
        toggleTheme: toggleTheme,
        textScale: _textScale,
        setTextScale: setTextScale,
        setLanguage: setLanguage,
        child: ValueListenableBuilder<String>(
          valueListenable: _languageController,
          builder: (context, languageCode, _) {
            final locale = Locale(languageCode, 'CA');
            return MaterialApp(
              navigatorKey: _navigatorKey,
              scaffoldMessengerKey: _scaffoldMessengerKey,
              debugShowCheckedModeBanner: false,
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              theme: lightTheme(),
              darkTheme: darkTheme(),
              themeMode: _themeMode,
              scrollBehavior: const AppScrollBehavior(),
              home: const OnboardingGate(),
              onGenerateRoute: AppRoutes.onGenerateRoute,
              builder: (context, child) {
                final media = MediaQuery.of(context);
                // Compose in-app text scale with the OS scale, capped at 2.2.
                final systemFactor = media.textScaler.scale(14) / 14;
                final effectiveScale = math.min(
                  _textScale * systemFactor,
                  2.2,
                );
                return MediaQuery(
                  data: media.copyWith(
                    textScaler: TextScaler.linear(effectiveScale),
                  ),
                  child: AppLock(
                    child: NoticeListener(
                      navigatorKey: _navigatorKey,
                      child: Column(
                        children: [
                          Expanded(child: child ?? const SizedBox.shrink()),
                          const OfflineBanner(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
