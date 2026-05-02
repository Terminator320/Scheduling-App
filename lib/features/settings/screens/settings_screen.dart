import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/master_detail_scaffold.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/security/biometric_auth_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/account_deletion_service.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/settings/application/app_info_provider.dart';
import 'package:scheduling/features/settings/application/app_lock_provider.dart';
import 'package:scheduling/features/settings/screens/text_size_screen.dart';
import 'package:scheduling/features/settings/widgets/cards/settings_tiles.dart';
import 'package:scheduling/features/settings/widgets/dialogs/delete_account_dialog.dart';
import 'package:scheduling/features/settings/widgets/views/text_size_view.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';

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

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final AccountDeletionService _deletionService =
      widget.accountDeletionService ?? AccountDeletionService();

  _SettingsDetail? _selectedDetail;

  String get _displayName {
    if (widget.name.isNotEmpty) return widget.name;
    // The name lives in the Firestore users doc, not Auth's displayName, so
    // fall back to the live doc when the screen is reached via the nav rail
    // (which doesn't thread the name through the constructor).
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
    if (context.isWide) {
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notifier = ThemeNotifier.of(context);
    final isDark = notifier.isDark;
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
        SettingsSectionCard(
          child: Column(
            children: [
              SettingsTile(
                iconBg: scheme.primaryContainer,
                icon: isDark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SettingsTrailingPill(
                      label: _textScaleLabel(context, notifier.textScale),
                    ),
                    const SizedBox(width: 4),
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
        ),
        const SizedBox(height: AppSpacing.sp24),
        SettingsSectionHeader(
          label: context.l10n.settings_account.toUpperCase(),
        ),
        SettingsSectionCard(
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
        ),
        const SizedBox(height: AppSpacing.sp24),
        SettingsSectionHeader(
          label: context.l10n.settings_security.toUpperCase(),
        ),
        SettingsSectionCard(
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
        ),
        const SizedBox(height: AppSpacing.sp24),
        _buildVersionFooter(scheme),
        const SizedBox(height: AppSpacing.sp32),
      ],
    );
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

  Widget _buildDetailPlaceholder() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sp24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              context.l10n.common_settings,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          context.l10n.common_settings,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
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
    );
  }

  Future<void> _signOut() async {
    await AuthService().signOut();
    if (!mounted) return;
    await Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (_) => false,
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          DeleteAccountDialog(isAdmin: widget.role == 'admin'),
    );
    if (result != true || !mounted) return;

    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const DeleteAccountReauthDialog(),
    );
    if (password == null || password.isEmpty || !mounted) return;

    await _runDeletion(password);
  }

  Future<void> _runDeletion(String password) async {
    final notices = ref.read(noticeServiceProvider);
    final logger = ref.read(loggerProvider);
    try {
      await _deletionService.reauthenticateWithPassword(password);
      await _deletionService.deleteAccount();
    } on AuthFailure catch (e) {
      if (!mounted) return;
      notices.error(e.toLocalizedMessage(context));
      return;
    } catch (e, st) {
      logger.warn('settings.delete_account', e, st);
      if (!mounted) return;
      notices.error(context.l10n.error_couldNotDeleteAccount);
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
