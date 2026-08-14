import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/app/device_deregistration.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/master_detail_scaffold.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/security/biometric_auth_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/account_deletion_service.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/feature_tour/application/tour_seen_store.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/domain/tour_steps.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
import 'package:scheduling/features/live_activity/application/live_activity_preference.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/navigation/widgets/app_nav_drawer.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/settings/application/app_info_provider.dart';
import 'package:scheduling/features/settings/application/app_lock_provider.dart';
import 'package:scheduling/features/settings/application/my_details_providers.dart';
import 'package:scheduling/features/settings/screens/text_size_screen.dart';
import 'package:scheduling/features/settings/widgets/cards/account_settings_card.dart';
import 'package:scheduling/features/settings/widgets/cards/appearance_settings_card.dart';
import 'package:scheduling/features/settings/widgets/cards/legal_settings_card.dart';
import 'package:scheduling/features/settings/widgets/cards/notifications_settings_card.dart';
import 'package:scheduling/features/settings/widgets/cards/security_settings_card.dart';
import 'package:scheduling/features/settings/widgets/cards/settings_tiles.dart';
import 'package:scheduling/features/settings/widgets/dialogs/delete_account_dialog.dart';
import 'package:scheduling/features/settings/widgets/views/text_size_view.dart';
import 'package:scheduling/features/wave/widgets/wave_settings_section.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/app_bars/app_header_pair.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';

enum _SettingsDetail { textSize }

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    this.name = '',
    this.email = '',
    this.role,
    this.employeeId = '',
    this.accountDeletionService,
  });

  final String name;
  final String email;
  final String? role;
  final String employeeId;
  final AccountDeletionService? accountDeletionService;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  late final AccountDeletionService _deletionService =
      widget.accountDeletionService ?? ref.read(accountDeletionServiceProvider);

  _SettingsDetail? _selectedDetail;
  bool _isSigningOut = false;
  bool _isDeletingAccount = false;

  late final _tour = TourSteps(
    const DestinationTour(PushedDestination.settings),
    isAdmin: widget.role == 'admin',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check on resume in case the user toggled notifications in OS Settings.
    if (state == AppLifecycleState.resumed && mounted) {
      ref
        ..invalidate(notificationAuthStatusProvider)
        // Live Activities support is also a cached, user-mutable OS Settings value.
        ..invalidate(liveActivitySupportedProvider);
      unawaited(ref.read(pushRegistrationControllerProvider).sync());
    }
  }

  String get _displayName {
    if (widget.name.isNotEmpty) return widget.name;

    final docName = ref.watch(currentUserNameProvider);
    if (docName.isNotEmpty) return docName;
    return FirebaseAuth.instance.currentUser?.displayName ?? '';
  }

  String get _email => widget.email.isNotEmpty
      ? widget.email
      : FirebaseAuth.instance.currentUser?.email ?? '';

  bool get _isAdmin => widget.role == 'admin';

  Future<void> _toggleAppLock({required bool value}) async {
    // Captured before the first await: `ref.read` throws once this consumer is
    // unmounted (Riverpod 3), and the catch below deliberately logs before its
    // mounted guard so the failure still reaches Crashlytics.
    final logger = ref.read(loggerProvider);
    if (value) {
      final available = await ref
          .read(biometricAuthServiceProvider)
          .isAvailable();
      if (!mounted) return;
      if (!available) {
        ref
            .read(noticeServiceProvider)
            .error(context.l10n.settings_appLockUnavailable);
        return;
      }
    }
    try {
      await ref.read(appLockEnabledProvider.notifier).setEnabled(value: value);
    } catch (e, st) {
      // flutter_secure_storage throws on an iOS keychain fault, including the
      // pre-first-unlock -25308 window AppLockController._load() documents by
      // name. Uncaught, that reached the zone handler as a FATAL and the
      // switch reverted silently. Same shape as OnboardingGate._finish.
      logger.warn('APPLOCK setEnabled failed', e, st);
      if (!mounted) return;
      ref
          .read(noticeServiceProvider)
          .error(
            composeErrorNotice(
              context,
              intro: context.l10n.error_introSaveAppLock,
              error: e,
            ),
          );
    }
  }

  Future<void> _onTextSizeTap() async {
    if (context.isTwoPane) {
      setState(() => _selectedDetail = _SettingsDetail.textSize);
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TextSizeScreen(
          isAdmin: _isAdmin,
          employeeId: widget.employeeId,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _buildMaster() {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      // Named so tests can target the master pane's scrollable directly: at
      // tablet-class viewports MasterDetailScaffold renders a second one, so
      // `find.byType(Scrollable).first` is ambiguous, and anchoring on a row
      // instead breaks whenever a row is added above it.
      key: const ValueKey('settingsMasterList'),
      // Inflate the whole list up front so below-the-fold feature-tour targets register.
      scrollCacheExtent: const ScrollCacheExtent.pixels(4000),
      padding: const EdgeInsets.all(AppSpacing.sp16),
      children: [
        SettingsProfileCard(
          name: _displayName,
          email: _email,
          role: widget.role,
        ),
        const SizedBox(height: AppSpacing.sp24),
        ..._settingsCards(scheme),
        ..._legalAndHelpCards(scheme),
        _buildVersionFooter(scheme),
        const SizedBox(height: AppSpacing.sp32),
      ],
    );
  }

  /// Turning this off unregisters the device, which ends any live card;
  /// turning it back on re-registers. Best effort — it never throws.
  Future<void> _toggleLiveActivity({required bool value}) async {
    // Both providers are resolved up front. This runs unawaited from
    // `Switch.onChanged`, so backing out of Settings mid-flight unmounts the
    // consumer — and under Riverpod 3 the second `ref.read` would then throw a
    // StateError into the void. This was the only async handler in this file
    // with no guard at all.
    final enabled = ref.read(liveActivityEnabledProvider.notifier);
    final controller = ref.read(liveActivityRegistrationControllerProvider);
    await enabled.setEnabled(value: value);
    if (value) {
      await controller.sync();
    } else {
      await controller.unregister();
    }
  }

  /// The traffic-aware departure push, per person.
  ///
  /// A SERVER-side flag, unlike the Live Activity toggle beside it: the sweep
  /// decides the push kind, so a device-local preference could not reach it.
  /// Turning it off degrades to the fixed 30-minute reminder rather than
  /// dropping the notification — see `wantsTravelAlerts` in
  /// `functions/travel_utils.js`.
  Future<void> _toggleTravelAlerts({required bool value}) async {
    final record = ref.read(myEmployeeRecordProvider);
    if (record == null) return;

    final l10n = context.l10n;
    final notices = ref.read(noticeServiceProvider);
    if (guardedOffline(context, ref, intro: l10n.error_introSaveTravelAlerts)) {
      return;
    }

    try {
      await ref
          .read(employeesRepositoryProvider)
          .updateSelfDetails(record.copyWith(travelAlertsEnabled: value));
    } catch (error, stackTrace) {
      ref
          .read(loggerProvider)
          .warn('ME-SAVE travel alerts failed', error, stackTrace);
      if (!mounted) return;
      notices.error(
        composeErrorNotice(
          context,
          intro: l10n.error_introSaveTravelAlerts,
          error: error,
        ),
      );
    }
  }

  /// notDetermined shows the one-time OS prompt; any other status opens OS Settings.
  Future<void> _onNotificationsTap(AuthorizationStatus status) async {
    final service = ref.read(pushNotificationServiceProvider);
    if (status == AuthorizationStatus.notDetermined) {
      await service.requestPermission();
    } else {
      await service.openSystemSettings();
    }
    if (!mounted) return;
    ref.invalidate(notificationAuthStatusProvider);
    unawaited(ref.read(pushRegistrationControllerProvider).sync());
  }

  Widget _helpCard(ColorScheme scheme) {
    return SettingsSectionCard(
      child: _tour.step(
        TourStepId.settingsReplay,
        child: SettingsTile(
          iconBg: scheme.primaryContainer,
          icon: Icons.tour_rounded,
          iconColor: scheme.primary,
          label: context.l10n.settings_replayTour,
          isLast: true,
          onTap: _onReplayTour,
        ),
      ),
    );
  }

  Future<void> _onReplayTour() async {
    await ref.read(tourSeenProvider.notifier).resetAll();
    if (!mounted) return;
    ref
        .read(noticeServiceProvider)
        .success(context.l10n.settings_replayTourDone);
  }

  Widget _buildVersionFooter(ColorScheme scheme) {
    final info = ref.watch(appInfoProvider);
    return Center(
      child: info.maybeWhen(
        data: (i) => Text(
          context.l10n.settings_version(i.version, i.buildNumber),
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }

  Widget? _buildDetail() {
    switch (_selectedDetail) {
      case _SettingsDetail.textSize:
        return TextSizeView(
          key: const ValueKey('settings-text-size-pane'),
          onApplied: () {
            if (mounted) setState(() => _selectedDetail = null);
          },
        );
      case null:
        return null;
    }
  }

  Widget _buildDetailPlaceholder() => DetailPlaceholder(
    icon: Icons.tune_rounded,
    message: context.l10n.common_settings,
  );

  @override
  Widget build(BuildContext context) {
    return FeatureTourHost(
      scope: _tour.scope,
      isAdmin: _isAdmin,
      stepKeys: _tour.keys,
      autoScroll: true,
      child: Stack(
        children: [
          Scaffold(
            appBar: AppTopBar(
              title: context.l10n.common_settings,
              compact: context.isLandscape,
              // A pushed route now, so back means back. The Calendar pill
              // covers go-home.
              onBack: () => Navigator.maybePop(context),
              actions: const [AppHeaderPair()],
            ),
            endDrawer: AppNavDrawer(
              isAdmin: _isAdmin,
              employeeId: widget.employeeId,
              userName: widget.name,
              email: widget.email,
            ),
            body: MasterDetailScaffold(
              master: _buildMaster(),
              detail: _buildDetail(),
              placeholder: _buildDetailPlaceholder(),
            ),
          ),
          // Blocks the UI during the irreversible account deletion.
          if (_isDeletingAccount)
            _BlockingProgressOverlay(
              label: context.l10n.settings_deletingAccount,
            ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    if (_isSigningOut) return;
    // Resolved before the de-registration round-trips: `ref.read` throws on an
    // unmounted consumer (Riverpod 3), and this catch is what guarantees the
    // user still reaches login rather than being stranded signed in.
    final logger = ref.read(loggerProvider);
    final authService = ref.read(authServiceProvider);
    setState(() => _isSigningOut = true);
    try {
      // Clean up this device's push token, presence, and Live Activity state
      // — best effort, so a failure here doesn't block sign-out. The ORDER is
      // owned by `deregisterThisDevice`; all three exits share it.
      await deregisterThisDevice(ref);
      await authService.signOut();
    } catch (e, st) {
      // Log but still route to login so the user isn't stuck signed in.
      logger.warn('ACCT-SIGNOUT signOut failed', e, st);
    }
    if (!mounted) return;
    await Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (_) => false,
    );
  }

  Future<void> _confirmDeleteAccount() async {
    if (_isDeletingAccount) return;
    // Bail out early if we're offline — otherwise the call just hangs for ~30s.
    if (guardedOffline(
      context,
      ref,
      intro: context.l10n.error_introDeleteAccount,
    )) {
      return;
    }
    final result = await showConfirmDialog(
      context,
      title: context.l10n.settings_deleteAccountConfirmTitle,
      confirmLabel: context.l10n.settings_deletePermanently,
      content: DeleteAccountWarningContent(isAdmin: _isAdmin),
    );
    if (!result || !mounted) return;

    // Match the platform presentation of the adaptive confirm dialog shown before this.
    final password = context.isCupertino
        ? await showCupertinoDialog<String>(
            context: context,
            builder: (dialogContext) => const DeleteAccountReauthDialog(),
          )
        : await showDialog<String>(
            context: context,
            builder: (dialogContext) => const DeleteAccountReauthDialog(),
          );
    if (password == null || password.isEmpty || !mounted) return;

    await _runDeletion(password);
  }

  Future<void> _runDeletion(String password) async {
    setState(() => _isDeletingAccount = true);
    final notices = ref.read(noticeServiceProvider);
    final logger = ref.read(loggerProvider);
    try {
      await _deletionService.reauthenticateWithPassword(password);
      // Drop this device's registrations while still authenticated, before
      // deleteAccount revokes access — same shared order as the other exits.
      await deregisterThisDevice(ref);
      await _deletionService.deleteAccount();
    } on AuthFailure catch (e, st) {
      // Logged before the mounted guard: this fires AFTER push, presence and
      // the Live Activity have already de-registered, so a half-torn-down
      // account must leave a trace. `authFailure` keeps a user-correctable
      // wrong password a breadcrumb and records the rest.
      logger.authFailure('ACCT-DEL settings.delete_account', e, e, st);
      if (!mounted) return;
      setState(() => _isDeletingAccount = false);
      notices.error(e.toLocalizedMessage(context));
      return;
    } catch (e, st) {
      logger.warn('ACCT-DEL settings.delete_account', e, st);
      if (!mounted) return;
      setState(() => _isDeletingAccount = false);
      notices.error(
        composeErrorNotice(
          context,
          intro: context.l10n.error_introDeleteAccount,
          error: e,
        ),
      );
      return;
    }
    if (!mounted) return;
    final message = context.l10n.settings_accountDeleted;
    await Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (_) => false,
    );
    notices.success(message);
  }

  /// Appearance, account, security, notifications and (admin-only) Wave.
  List<Widget> _settingsCards(ColorScheme scheme) => [
    SettingsSectionHeader(
      label: context.l10n.settings_appearance.toUpperCase(),
    ),
    _tour.step(
      TourStepId.settingsAppearance,
      child: AppearanceSettingsCard(onTextSizeTap: _onTextSizeTap),
    ),
    const SizedBox(height: AppSpacing.sp24),
    SettingsSectionHeader(
      label: context.l10n.settings_account.toUpperCase(),
    ),
    SettingsSectionCard(
      child: SettingsTile(
        iconBg: scheme.primaryContainer,
        icon: Icons.badge_outlined,
        iconColor: scheme.primary,
        label: context.l10n.settings_myDetails,
        isLast: true,
        onTap: () => Navigator.pushNamed(context, AppRoutes.myDetails),
      ),
    ),
    const SizedBox(height: AppSpacing.sp12),
    AccountSettingsCard(
      onSignOut: _signOut,
      onDeleteAccount: _confirmDeleteAccount,
    ),
    const SizedBox(height: AppSpacing.sp24),
    SettingsSectionHeader(
      label: context.l10n.settings_security.toUpperCase(),
    ),
    SecuritySettingsCard(onToggleAppLock: _toggleAppLock),
    const SizedBox(height: AppSpacing.sp24),
    SettingsSectionHeader(
      label: context.l10n.settings_notifications.toUpperCase(),
    ),
    _tour.step(
      TourStepId.settingsNotifications,
      child: NotificationsSettingsCard(
        onNotificationsTap: _onNotificationsTap,
        onToggleLiveActivity: _toggleLiveActivity,
        // Null hides the row until the person's own record has loaded —
        // rendering the switch against a guessed default would show a state
        // that may be wrong and then flip under them.
        travelAlertsEnabled: ref
            .watch(myEmployeeRecordProvider)
            ?.travelAlertsEnabled,
        onToggleTravelAlerts: _toggleTravelAlerts,
      ),
    ),
    if (_isAdmin) ...[
      const SizedBox(height: AppSpacing.sp24),
      SettingsSectionHeader(
        label: context.l10n.settings_integrations.toUpperCase(),
      ),
      const SettingsSectionCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sp12),
          child: WaveSettingsSection(),
        ),
      ),
    ],
    const SizedBox(height: AppSpacing.sp24),
  ];

  List<Widget> _legalAndHelpCards(ColorScheme scheme) => [
    SettingsSectionHeader(
      label: context.l10n.settings_legal.toUpperCase(),
    ),
    const LegalSettingsCard(),
    const SizedBox(height: AppSpacing.sp24),
    SettingsSectionHeader(
      label: context.l10n.settings_help.toUpperCase(),
    ),
    _helpCard(scheme),
    const SizedBox(height: AppSpacing.sp24),
  ];
}

/// Full-screen modal barrier + spinner shown while a blocking, irreversible operation runs.
class _BlockingProgressOverlay extends StatelessWidget {
  const _BlockingProgressOverlay({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Stack(
        children: [
          ModalBarrier(
            dismissible: false,
            color: scheme.scrim.withValues(alpha: 0.54),
          ),
          Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sp24),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AdaptiveProgressIndicator(),
                    const SizedBox(width: AppSpacing.sp16),
                    Flexible(child: Text(label)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
