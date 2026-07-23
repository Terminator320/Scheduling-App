import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/constants/app_urls.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/launchers/web_url_launcher.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/master_detail_scaffold.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/notifications/push_notification_service.dart';
import 'package:scheduling/core/security/biometric_auth_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/account_deletion_service.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/feature_tour/application/tour_seen_store.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
import 'package:scheduling/features/feature_tour/widgets/tour_showcase.dart';
import 'package:scheduling/features/live_activity/application/live_activity_preference.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';
import 'package:scheduling/features/settings/application/app_info_provider.dart';
import 'package:scheduling/features/settings/application/app_lock_provider.dart';
import 'package:scheduling/features/settings/screens/text_size_screen.dart';
import 'package:scheduling/features/settings/widgets/cards/settings_tiles.dart';
import 'package:scheduling/features/settings/widgets/dialogs/delete_account_dialog.dart';
import 'package:scheduling/features/settings/widgets/views/text_size_view.dart';
import 'package:scheduling/features/wave/widgets/wave_settings_section.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';
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

  late final List<TourStepId> _tourSteps = tourStepsFor(
    AdaptiveDestination.settings,
    isAdmin: widget.role == 'admin',
  );
  late final Map<TourStepId, GlobalKey> _tourKeys = {
    for (final id in _tourSteps) id: GlobalKey(),
  };

  Widget _tourStep(TourStepId id, {required Widget child}) => TourShowcase(
    showcaseKey: _tourKeys[id]!,
    tab: AdaptiveDestination.settings,
    id: id,
    index: _tourSteps.indexOf(id),
    count: _tourSteps.length,
    child: child,
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
    // Returning from the OS Settings app (where the user may have just toggled
    // notifications on) — re-read the status so the row updates, and re-run
    // registration so a newly-granted device actually gets its FCM token
    // stored server-side. Without the re-sync, "enabled in Settings" would
    // still deliver no pushes.
    if (state == AppLifecycleState.resumed && mounted) {
      ref
        ..invalidate(notificationAuthStatusProvider)
        // Same reasoning for Live Activities: `areActivitiesEnabled()` is a
        // user-mutable iOS Settings value, and the probe is cached for the
        // process lifetime — without this the row stays "unsupported" until
        // the app is relaunched.
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

  String _textScaleLabel(BuildContext context, double scale) {
    if (scale <= 0.85) return context.l10n.settings_textScaleSmall;
    if (scale <= 1.05) return context.l10n.settings_textScaleMedium;
    if (scale <= 1.25) return context.l10n.settings_textScaleLarge;
    return context.l10n.settings_textScaleXL;
  }

  bool get _isAdmin => widget.role == 'admin';

  Future<void> _toggleAppLock({required bool value}) async {
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
    await ref.read(appLockEnabledProvider.notifier).setEnabled(value: value);
  }

  Future<void> _onTextSizeTap() async {
    if (context.isTwoPane) {
      setState(() => _selectedDetail = _SettingsDetail.textSize);
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const TextSizeScreen()),
    );
    if (mounted) setState(() {});
  }

  Widget _buildMaster() {
    final scheme = Theme.of(context).colorScheme;
    final notifier = ThemeNotifier.of(context);
    final langCode = Localizations.localeOf(context).languageCode;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.sp16),
      children: [
        SettingsProfileCard(
          name: _displayName,
          email: _email,
          role: widget.role,
        ),
        const SizedBox(height: AppSpacing.sp24),
        SettingsSectionHeader(
          label: context.l10n.settings_appearance.toUpperCase(),
        ),
        _tourStep(
          TourStepId.settingsAppearance,
          child: _appearanceCard(scheme, notifier, langCode: langCode),
        ),
        const SizedBox(height: AppSpacing.sp24),
        SettingsSectionHeader(
          label: context.l10n.settings_account.toUpperCase(),
        ),
        _accountCard(scheme),
        const SizedBox(height: AppSpacing.sp24),
        SettingsSectionHeader(
          label: context.l10n.settings_security.toUpperCase(),
        ),
        _securityCard(scheme),
        const SizedBox(height: AppSpacing.sp24),
        SettingsSectionHeader(
          label: context.l10n.settings_notifications.toUpperCase(),
        ),
        _tourStep(
          TourStepId.settingsNotifications,
          child: _notificationsCard(scheme),
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
        SettingsSectionHeader(
          label: context.l10n.settings_legal.toUpperCase(),
        ),
        _legalCard(scheme),
        const SizedBox(height: AppSpacing.sp24),
        SettingsSectionHeader(
          label: context.l10n.settings_help.toUpperCase(),
        ),
        _helpCard(scheme),
        const SizedBox(height: AppSpacing.sp24),
        _buildVersionFooter(scheme),
        const SizedBox(height: AppSpacing.sp32),
      ],
    );
  }

  Widget _appearanceCard(
    ColorScheme scheme,
    ThemeNotifier notifier, {
    required String langCode,
  }) {
    // Resolve against the live OS brightness via MediaQuery so the switch both
    // matches what's on screen under the default `system` mode and rebuilds if
    // the OS theme flips while this screen is open.
    final isDark = isDarkMode(
      notifier.themeMode,
      MediaQuery.platformBrightnessOf(context),
    );
    return SettingsSectionCard(
      child: Column(
        children: [
          SettingsTile(
            iconBg: scheme.primaryContainer,
            icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            iconColor: scheme.primary,
            label: context.l10n.settings_darkMode,
            trailing: Switch.adaptive(
              value: isDark,
              onChanged: (_) => notifier.toggleTheme(),
              activeTrackColor: scheme.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SettingsTileDivider(),
          SettingsTile(
            iconBg: scheme.tertiaryContainer,
            icon: Icons.text_fields_rounded,
            iconColor: scheme.tertiary,
            label: context.l10n.settings_textSize,
            trailing: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sp4,
              runSpacing: AppSpacing.sp4,
              children: [
                SettingsTrailingPill(
                  label: _textScaleLabel(context, notifier.textScale),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            onTap: _onTextSizeTap,
          ),
          const SettingsTileDivider(),
          SettingsTile(
            iconBg: scheme.secondaryContainer,
            icon: Icons.language_rounded,
            iconColor: scheme.secondary,
            label: context.l10n.common_language,
            trailing: LanguageToggle(
              currentCode: langCode,
              onChanged: notifier.setLanguage,
            ),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _notificationsCard(ColorScheme scheme) {
    // valueOrNull keeps the row rendering during the first async read; default
    // to notDetermined so the row offers the enable action rather than a
    // misleading "On" before the status resolves.
    final status =
        ref.watch(notificationAuthStatusProvider).asData?.value ??
        AuthorizationStatus.notDetermined;
    final granted = PushNotificationService.isGranted(status);
    // Hidden off iOS, below 17.2, and when the user turned Live Activities off
    // in iOS Settings — a device that can't host the card gets no control at
    // all rather than a permanently dead switch.
    final showLiveActivity =
        ref.watch(liveActivitySupportedProvider).asData?.value ?? false;
    return SettingsSectionCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsTile(
            iconBg: granted ? scheme.primaryContainer : scheme.errorContainer,
            icon: granted
                ? Icons.notifications_active_rounded
                : Icons.notifications_off_rounded,
            iconColor: granted ? scheme.primary : scheme.error,
            label: context.l10n.settings_notifications,
            isLast: !showLiveActivity,
            trailing: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sp4,
              runSpacing: AppSpacing.sp4,
              children: [
                SettingsTrailingPill(
                  label: granted
                      ? context.l10n.settings_notificationsOn
                      : context.l10n.settings_notificationsOff,
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            onTap: () => _onNotificationsTap(status),
          ),
          if (showLiveActivity) ...[
            const SettingsTileDivider(),
            SettingsTile(
              iconBg: scheme.primaryContainer,
              icon: Icons.directions_car_rounded,
              iconColor: scheme.primary,
              label: context.l10n.settings_liveActivity,
              isLast: true,
              trailing: Switch.adaptive(
                value: ref.watch(liveActivityEnabledProvider),
                onChanged: (value) => _toggleLiveActivity(value: value),
                activeTrackColor: scheme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Turning the card OFF must do more than set a flag: the server *push-starts*
  /// it, so a registered token would keep producing cards. Unregistering ends
  /// any live card and deletes this device's token rows; turning it back on
  /// re-registers. Both are best-effort and never throw.
  Future<void> _toggleLiveActivity({required bool value}) async {
    await ref
        .read(liveActivityEnabledProvider.notifier)
        .setEnabled(value: value);
    final controller = ref.read(liveActivityRegistrationControllerProvider);
    if (value) {
      await controller.sync();
    } else {
      await controller.unregister();
    }
  }

  /// notDetermined → show the one-time OS prompt (the app updated but the ask
  /// never fired for this user). Any other non-granted state can ONLY be
  /// recovered from the OS Settings app — iOS never re-shows the system dialog
  /// once it has been answered. Granted taps also open Settings so the user can
  /// fine-tune or turn it off. Either way, re-read the status and re-register.
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

  Widget _accountCard(ColorScheme scheme) {
    return SettingsSectionCard(
      child: Column(
        children: [
          SettingsTile(
            iconBg: scheme.errorContainer,
            icon: Icons.logout_rounded,
            iconColor: scheme.error,
            label: context.l10n.settings_logOut,
            labelColor: scheme.error,
            onTap: _signOut,
          ),
          const SettingsTileDivider(),
          SettingsTile(
            iconBg: scheme.errorContainer,
            icon: Icons.delete_forever_rounded,
            iconColor: scheme.error,
            label: context.l10n.settings_deleteAccount,
            labelColor: scheme.error,
            isLast: true,
            onTap: _confirmDeleteAccount,
          ),
        ],
      ),
    );
  }

  Widget _securityCard(ColorScheme scheme) {
    return SettingsSectionCard(
      child: SettingsTile(
        iconBg: scheme.primaryContainer,
        icon: Icons.fingerprint_rounded,
        iconColor: scheme.primary,
        label: context.l10n.settings_appLock,
        isLast: true,
        trailing: Switch.adaptive(
          value: ref.watch(appLockEnabledProvider),
          onChanged: (value) => _toggleAppLock(value: value),
          activeTrackColor: scheme.primary,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Widget _legalCard(ColorScheme scheme) {
    return SettingsSectionCard(
      child: SettingsTile(
        iconBg: scheme.secondaryContainer,
        icon: Icons.privacy_tip_rounded,
        iconColor: scheme.secondary,
        label: context.l10n.settings_privacyPolicy,
        isLast: true,
        trailing: Icon(
          Icons.open_in_new_rounded,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        onTap: () => launchWebUrl(context, ref, AppUrls.privacyPolicy),
      ),
    );
  }

  Widget _helpCard(ColorScheme scheme) {
    return SettingsSectionCard(
      child: _tourStep(
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
      tab: AdaptiveDestination.settings,
      isAdmin: _isAdmin,
      stepKeys: _tourKeys,
      child: Stack(
        children: [
          Scaffold(
            appBar: AppTopBar(
              title: context.l10n.common_settings,
              compact: context.isLandscape,
              onBack: () => navigateToDestination(
                context,
                AdaptiveDestination.calendar,
                isAdmin: _isAdmin,
                employeeId: widget.employeeId,
              ),
            ),
            body: AdaptiveShell(
              currentDestination: AdaptiveDestination.settings,
              isAdmin: _isAdmin,
              employeeId: widget.employeeId,
              userName: _displayName,
              userEmail: _email,
              child: MasterDetailScaffold(
                master: _buildMaster(),
                detail: _buildDetail(),
                placeholder: _buildDetailPlaceholder(),
              ),
            ),
          ),
          // Blocks the UI during the multi-second, irreversible account
          // deletion so it can't be re-triggered and the user sees progress.
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
    setState(() => _isSigningOut = true);
    try {
      // Best-effort: drop this device's push token, live location and Live
      // Activity cards/tokens before the session ends.
      await ref
          .read(pushRegistrationControllerProvider)
          .unregisterCurrentDevice();
      await ref.read(presenceSyncControllerProvider).unregister();
      await ref.read(liveActivityRegistrationControllerProvider).unregister();
      await ref.read(authServiceProvider).signOut();
    } catch (e, st) {
      // signOut clears local state and effectively never throws; if it does,
      // log it but still route to login so the user isn't stuck signed in.
      ref.read(loggerProvider).warn('ACCT-SIGNOUT signOut failed', e, st);
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
    // Fail fast offline: the deleteAccount callable would otherwise hang ~30 s.
    if (ref.read(isOfflineProvider)) {
      ref
          .read(noticeServiceProvider)
          .error(
            composeErrorNotice(
              context,
              intro: context.l10n.error_introDeleteAccount,
              tag: 'ACCT-DEL',
              error: const SocketException('offline'),
            ),
          );
      return;
    }
    final result = await showConfirmDialog(
      context,
      title: context.l10n.settings_deleteAccountConfirmTitle,
      confirmLabel: context.l10n.settings_deletePermanently,
      content: DeleteAccountWarningContent(isAdmin: _isAdmin),
    );
    if (!result || !mounted) return;

    // Platform-matched presentation so the re-auth prompt looks like the
    // adaptive confirm it directly follows.
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
      // Best-effort: drop this device's push token while still authenticated —
      // after deleteAccount removes the users doc the rules would reject the
      // token delete, leaving an orphan fcmTokens doc behind. Also stop the
      // location stream (the server's recursiveDelete removes the presence
      // doc itself).
      await ref
          .read(pushRegistrationControllerProvider)
          .unregisterCurrentDevice();
      await ref.read(presenceSyncControllerProvider).unregister();
      await ref.read(liveActivityRegistrationControllerProvider).unregister();
      await _deletionService.deleteAccount();
    } on AuthFailure catch (e) {
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
          tag: 'ACCT-DEL',
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
}

/// Full-screen modal barrier + spinner shown while a blocking, irreversible
/// operation runs. The [ModalBarrier] absorbs all input so the action behind
/// it can't be re-triggered.
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
