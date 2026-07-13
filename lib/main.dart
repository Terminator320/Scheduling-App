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
import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/connectivity/offline_banner.dart';
import 'package:scheduling/core/logging/app_logger.dart';
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
import 'package:scheduling/features/calendar/data/appointment_image_upload_service.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/home_widget/application/widget_sync_service.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';
import 'package:scheduling/features/onboarding/screens/onboarding_gate.dart';
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

      await Future.wait([
        initializeDateFormatting('en_CA'),
        initializeDateFormatting('fr_CA'),
        dotenv.load(fileName: 'dev/.env'),
      ]);

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Pin the offline cache explicitly so an SDK default-flip can never
      // silently drop it. Must run before the first Firestore read (it does —
      // SplashScreen reads later).
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
      );

      // Wake-on-push widget refresh (iOS): a change push carries a fresh
      // widgetPayload + content-available, so this fires in its own isolate
      // with the app closed/backgrounded and rewrites the home-screen widget.
      // Must be registered before runApp with a top-level handler.
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      Future<void> firebaseReady;
      if (_useFirebaseEmulator) {
        await _wireFirebaseEmulator();
        firebaseReady = Future<void>.value();
      } else {
        // Error handlers are plain assignments: wire them synchronously so
        // nothing is missed while the activation futures are in flight.
        final crashlytics = FirebaseCrashlytics.instance;
        FlutterError.onError = crashlytics.recordFlutterFatalError;
        PlatformDispatcher.instance.onError = (error, stack) {
          crashlytics.recordError(error, stack, fatal: true);
          return true;
        };

        // Deliberately not awaited. If activation fails before anything
        // subscribes to firebaseReadyProvider, the zone handler below
        // records it; subscribers observe the same error via the provider.
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
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
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

  /// Home-widget taps (iOS only) deep-link to the tapped job's appointment.
  /// The Swift widget links each row / the small-widget card to
  /// `esproschedule://appointment?id=<id>`; home_widget surfaces that URI here.
  void _setupWidgetTapHandling() {
    if (!Platform.isIOS) return;
    // Register the App Group BEFORE any widget read — home_widget throws
    // `AppGroupId not set` otherwise, and the launch-from-widget tap below is
    // the first read on a cold start (the sync service that also sets it only
    // runs after the first account emission).
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
    // A failed deep-link open is a non-crash — swallow it here so the async
    // handler can't leak an unhandled rejection into runZonedGuarded /
    // PlatformDispatcher.onError, which would record it as a FATAL crash.
    try {
      await _openAppointmentDeepLink(appointmentId);
    } catch (e, st) {
      ref.read(loggerProvider).warn('WIDGET-TAP open failed', e, st);
    }
  }

  /// Notification taps (terminated launch + background) open the tapped
  /// appointment's detail sheet on the calendar hub. Every per-appointment
  /// push carries `data.appointmentId` (assignment / reschedule / cancel /
  /// removal / reminder / done-check); the daily digest carries none and just
  /// lands on the calendar.
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
    // A failed deep-link open is a non-crash — swallow it here so the async
    // handler can't leak an unhandled rejection into runZonedGuarded /
    // PlatformDispatcher.onError, which would record it as a FATAL crash.
    try {
      await _openAppointmentDeepLink(appointmentId);
    } catch (e, st) {
      ref.read(loggerProvider).warn('PUSH-TAP open failed', e, st);
    }
  }

  /// Shared deep-link target for a notification or home-widget tap: brings the
  /// live hub to the calendar tab, collapses any stacked routes, then opens the
  /// appointment's detail sheet. An empty/missing id (digest, or a widget tap
  /// with no appointment) just surfaces the calendar. A missing appointment
  /// (deleted / no longer visible) surfaces an info notice instead.
  Future<void> _openAppointmentDeepLink(String appointmentId) async {
    if (FirebaseAuth.instance.currentUser == null) return;

    // Fetch the appointment concurrently with the (cold-launch: multi-second)
    // wait for the hub — the read doesn't depend on the hub being alive, so
    // overlapping it hides the network round-trip behind the splash/routing
    // wait. One retry survives the post-sign-in `permission-denied` race while
    // the auth token propagates (a missing doc returns null, not an error, so
    // it isn't retried). `.catchError` keeps this a non-throwing future so an
    // early bail-out below can't leak an unhandled rejection.
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

    // Terminated-launch taps fire before the post-login hub is built (splash
    // routes into it), so wait briefly for it to come alive.
    final shell = await _awaitLiveHub();
    if (shell == null || !mounted) return;
    shell.showCalendar();

    final record = await recordFuture;
    if (!mounted) return;

    final navContext = _navigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;
    // Collapse any detail/edit sheet or pushed route so the target opens over
    // the calendar root.
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
    await showEventDetails(navContext, record);
  }

  /// Polls up to ~10s for the live hub. Background taps resolve on the first
  /// tick (the hub is already up); a cold launch waits out splash + routing.
  /// Returns null if the hub never appears (e.g. the user is stuck on login).
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
    // Flip whatever is on screen now — resolving the default `system` mode
    // against the live OS brightness — so one tap always changes the
    // appearance (no more "toggle twice" on a dark phone).
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
    // The iOS home widget localizes its chrome/status labels from the payload's
    // `locale`; recompute the payload so the widget follows the app language
    // instead of waiting for the next appointment-stream emission.
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
      // Best-effort device de-registration first — sign-out must not be blocked
      // by it (the controller swallows its own failures).
      await ref
          .read(pushRegistrationControllerProvider)
          .unregisterCurrentDevice();
      await ref.read(presenceSyncControllerProvider).unregister();
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
      // Sign-out failed (network/plugin) — the next signal retries.
      ref.read(loggerProvider).warn('ACCOUNT-EXIT sign-out failed', e, st);
    } finally {
      // Reset on failure too, or every later disabled/deleted signal is muted.
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

  void _listenForPushRegistration() {
    // Registers this device's FCM token when an active employee's or admin's
    // account doc resolves (admins get time-based nudges for jobs they're
    // assigned to); a no-op for signed-out users.
    ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
      prev,
      next,
    ) {
      unawaited(ref.read(pushRegistrationControllerProvider).sync());
    });
    // Also sync against a value already present at registration: on relaunch
    // while already authenticated, the employee doc can resolve before this
    // listener is set up, and a plain listen would miss it (no prompt / no
    // token registration). Harmless when the doc isn't ready yet — the gate
    // returns early and the listener above catches the later emission.
    unawaited(ref.read(pushRegistrationControllerProvider).sync());
  }

  void _listenForPresenceSync() {
    // Starts/stops the background location stream that feeds the travel-time
    // "leave now" reminders — active employees only (admins are never
    // tracked). Same emission-driven shape as push registration above.
    ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
      prev,
      next,
    ) {
      unawaited(ref.read(presenceSyncControllerProvider).sync());
    });
    unawaited(ref.read(presenceSyncControllerProvider).sync());
  }

  void _listenForWidgetSync() {
    // iOS home-screen widget only. On Android (dev harness) this never wires,
    // so the employee-appointments listener it would open is never opened.
    if (!Platform.isIOS) return;
    ref.listen<AsyncValue<Map<String, dynamic>?>>(widgetPayloadProvider, (
      prev,
      next,
    ) {
      final payload = next.value;
      final service = ref.read(widgetSyncServiceProvider);
      if (payload == null) {
        unawaited(service.clear());
      } else {
        unawaited(service.sync(payload));
      }
    });
  }

  void _listenForUploadDrain() {
    // Reconnect: retry queued photo batches once per offline→online flip.
    ref.listen<bool>(isOfflineProvider, (previous, next) {
      final isSignedIn =
          ref.read(currentUserDocProvider).value?.isNotEmpty ?? false;
      if (previous == true && !next && isSignedIn) {
        unawaited(ref.read(appointmentImageUploadProvider).drainPending());
      }
    });
    // Startup / sign-in: one drain when the account doc first arrives (Storage
    // rules need an authed user; a signed-out drain would just re-queue).
    ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
      previous,
      next,
    ) {
      final wasEmpty = previous?.value?.isEmpty ?? true;
      final hasDoc = next.value?.isNotEmpty ?? false;
      if (wasEmpty && hasDoc) {
        unawaited(ref.read(appointmentImageUploadProvider).drainPending());
      }
    });
  }

  void _listenForRoleRevocation() {
    ref.listen<AsyncValue<String>>(userRoleProvider, (prev, next) {
      final prevRole = prev?.value;
      final nextRole = next.value;
      // An empty new role means the doc went populated→empty — that's an
      // account deletion, not a demotion. Let `_listenForDeletedAccount` own it
      // (both funnel through the shared `_isHandlingAccountExit` flag, and this
      // listener is registered first) so the user gets the "disabled" message,
      // not "admin access revoked".
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
      // Kick-out: populated→empty = runtime delete; cold start handled below.
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
    _listenForPushRegistration();
    _listenForPresenceSync();
    _listenForWidgetSync();
    _listenForUploadDrain();
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
