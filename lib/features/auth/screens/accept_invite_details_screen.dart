import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/core/validators/phone_format.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/auth/application/sign_in_controller.dart';
import 'package:scheduling/features/auth/data/auth_error_mapper.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/auth/widgets/auth_banner.dart';
import 'package:scheduling/features/auth/widgets/auth_form_widgets.dart';
import 'package:scheduling/features/auth/widgets/password_requirements_checklist.dart';
import 'package:scheduling/features/auth/widgets/password_strength_meter.dart';
import 'package:scheduling/features/employees/domain/models/invite_preview.dart';
import 'package:scheduling/features/settings/domain/role_label.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';

/// Second half of the invite acceptance flow: everything the new account needs
/// that the invite could not supply.
///
/// The email is NOT asked for — it comes from the invite via `previewInvite`
/// and is rendered locked, because it is the address the server re-checks the
/// code against at redeem time. The code rides [code] from the previous
/// screen, so acceptance never re-asks for it.
class AcceptInviteDetailsScreen extends ConsumerStatefulWidget {
  const AcceptInviteDetailsScreen({
    required this.code,
    required this.preview,
    this.authService,
    super.key,
  });

  /// Already normalized by the code screen. A credential — it stays on the
  /// navigator stack and dies with this route.
  final String code;
  final InvitePreview preview;
  final AuthService? authService;

  @override
  ConsumerState<AcceptInviteDetailsScreen> createState() =>
      _AcceptInviteDetailsScreenState();
}

class _AcceptInviteDetailsScreenState
    extends ConsumerState<AcceptInviteDetailsScreen> {
  late final AuthService _authService =
      widget.authService ?? ref.read(authServiceProvider);

  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  final FocusNode _lastNameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  bool _isObscured = true;
  bool _isConfirmObscured = true;
  bool _consented = false;
  bool _isLoading = false;
  bool _submitted = false;
  bool _codeDied = false;

  String? _firstNameError;
  String? _lastNameError;
  String? _passwordError;
  String? _confirmError;
  String? _bannerError;
  String? _bannerSuccess;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(
      text: widget.preview.firstName,
    );
    _lastNameController = TextEditingController(text: widget.preview.lastName);
  }

  @override
  void dispose() {
    for (final controller in [
      _firstNameController,
      _lastNameController,
      _phoneController,
      _passwordController,
      _confirmController,
    ]) {
      controller.dispose();
    }
    for (final node in [
      _lastNameFocus,
      _phoneFocus,
      _passwordFocus,
      _confirmFocus,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  bool _validate() {
    final l10n = context.l10n;
    final required = l10n.validation_nameIsRequired;
    final firstErr = _firstNameController.text.trim().isEmpty ? required : null;
    final lastErr = _lastNameController.text.trim().isEmpty ? required : null;
    // The meter beside this field is advisory; the gate stays the strict
    // new-password validator so it can never disagree with the checklist.
    final passwordErr = AuthValidators.newPassword(
      context,
      _passwordController.text,
    );

    String? confirmErr;
    if (_confirmController.text.trim().isEmpty) {
      confirmErr = l10n.validation_pleaseConfirmYourPassword;
    } else if (_confirmController.text.trim() !=
        _passwordController.text.trim()) {
      confirmErr = l10n.validation_passwordsDoNotMatch;
    }

    setState(() {
      _firstNameError = firstErr;
      _lastNameError = lastErr;
      _passwordError = passwordErr;
      _confirmError = confirmErr;
    });

    return firstErr == null &&
        lastErr == null &&
        passwordErr == null &&
        confirmErr == null;
  }

  void _onFieldChanged() {
    if (_submitted) _validate();
    if (_bannerError != null) setState(() => _bannerError = null);
  }

  void _onPasswordChanged() {
    // Rebuild so the meter and the checklist track every keystroke.
    setState(() {});
    _onFieldChanged();
  }

  Future<void> _createAccount() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _submitted = true;
      _bannerError = null;
      _codeDied = false;
    });

    if (!_validate()) return;

    // Before the in-flight flag: an awaited write offline never resolves until
    // the connection returns, so Save would just spin.
    if (ref.read(isOfflineProvider)) {
      setState(() {
        _bannerError = const AuthFailureNetwork().toLocalizedMessageInContext(
          context,
          AuthErrorContext.register,
        );
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.signUpWithCode(
        email: widget.preview.email,
        password: _passwordController.text,
        code: widget.code,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
        termsAccepted: true,
        locationConsent: true,
      );
      // Success only — a failed attempt must never ask the OS to save it.
      TextInput.finishAutofillContext();
      if (!mounted) return;
      await _routeAfterSignUp();
    } catch (error, stackTrace) {
      final failure = AuthErrorMapper.map(error);
      ref
          .read(loggerProvider)
          .authFailure(
            'AUTH-ACCEPT signUpWithCode failed',
            failure,
            error,
            stackTrace,
          );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _bannerError = failure.toLocalizedMessageInContext(
          context,
          AuthErrorContext.register,
        );
        // The code died between preview and submit — expired in the window,
        // revoked, or redeemed elsewhere. Offer the way back.
        _codeDied =
            failure is AuthFailureInvalidSignupCode ||
            failure is AuthFailureSignupCodeExpired;
      });
    }
  }

  /// Redemption leaves us signed in, so resolve the freshly activated profile
  /// and go straight into the app.
  Future<void> _routeAfterSignUp() async {
    final outcome = await ref
        .read(signInControllerProvider.notifier)
        .resumeAfterSignUp();
    if (!mounted) return;
    switch (outcome) {
      case SignInSuccess(:final employee):
        await Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.mainCalendar,
          (_) => false,
          arguments: MainCalendarArgs(
            isAdmin: employee.isAdmin,
            employeeId: employee.id,
          ),
        );
      // The account exists and is active server-side; the doc just isn't
      // readable yet. Say so and offer the way back to sign-in.
      case SignInNoSession() || SignInProfilePending():
        setState(() {
          _isLoading = false;
          _bannerSuccess = context.l10n.auth_accountCreatedYouCanNowSignIn;
        });
      // These only come from signIn() — resumeAfterSignUp() never produces
      // them, but the sealed family forces the branch.
      case SignInInvalidCredentials() ||
          SignInNoProfile() ||
          SignInAccountDisabled() ||
          SignInError():
        break;
    }
  }

  void _backToSignIn() {
    Navigator.of(
      context,
    ).popUntil((route) => route.settings.name == AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final bannerSuccess = _bannerSuccess;

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.auth_acceptInviteTitle,
            style: theme.textTheme.headlineLarge,
          ),
          const SizedBox(height: AppSpacing.sp16),
          _InviteBanner(preview: widget.preview),
          const SizedBox(height: AppSpacing.sp16),
          _LockedEmailPanel(email: widget.preview.email),
          const SizedBox(height: AppSpacing.sp16),
          LabeledTextField(
            key: const Key('firstName'),
            label: l10n.employees_firstName,
            controller: _firstNameController,
            required: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.givenName],
            maxLength: TextLimits.firstName,
            errorText: _firstNameError,
            onChanged: (_) => _onFieldChanged(),
            onSubmitted: (_) => _lastNameFocus.requestFocus(),
          ),
          const SizedBox(height: AppSpacing.sp16),
          LabeledTextField(
            key: const Key('lastName'),
            label: l10n.employees_lastName,
            controller: _lastNameController,
            focusNode: _lastNameFocus,
            required: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.familyName],
            maxLength: TextLimits.lastName,
            errorText: _lastNameError,
            onChanged: (_) => _onFieldChanged(),
            onSubmitted: (_) => _phoneFocus.requestFocus(),
          ),
          const SizedBox(height: AppSpacing.sp16),
          LabeledTextField(
            key: const Key('phone'),
            label: l10n.employees_phoneNumber,
            controller: _phoneController,
            focusNode: _phoneFocus,
            optional: true,
            keyboard: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: const [PhoneInputFormatter()],
            maxLength: TextLimits.phone,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: AppSpacing.sp16),
          AuthPasswordField(
            label: l10n.common_password,
            showLabel: true,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            controller: _passwordController,
            focusNode: _passwordFocus,
            enabled: !_isLoading,
            errorText: _passwordError,
            isObscured: _isObscured,
            onSubmitted: _confirmFocus.requestFocus,
            onChanged: _onPasswordChanged,
            onToggleObscured: () => setState(() => _isObscured = !_isObscured),
          ),
          const SizedBox(height: AppSpacing.sp8),
          PasswordStrengthMeter(password: _passwordController.text),
          const SizedBox(height: AppSpacing.sp8),
          PasswordRequirementsChecklist(password: _passwordController.text),
          const SizedBox(height: AppSpacing.sp16),
          AuthPasswordField(
            label: l10n.auth_confirmPassword,
            showLabel: true,
            prefixIcon: Icons.lock_reset_outlined,
            autofillHints: const [AutofillHints.newPassword],
            controller: _confirmController,
            focusNode: _confirmFocus,
            enabled: !_isLoading,
            errorText: _confirmError,
            isObscured: _isConfirmObscured,
            onSubmitted: _createAccount,
            onChanged: _onFieldChanged,
            onToggleObscured: () =>
                setState(() => _isConfirmObscured = !_isConfirmObscured),
          ),
          const SizedBox(height: AppSpacing.sp24),
          _ConsentRow(
            value: _consented,
            enabled: !_isLoading,
            onChanged: (value) => setState(() => _consented = value),
          ),
          AuthBanner(message: _bannerError),
          if (bannerSuccess != null)
            AuthBanner(
              message: bannerSuccess,
              kind: AuthBannerKind.success,
            ),
          const SizedBox(height: AppSpacing.sp24),
          AnimatedLoadingButton(
            label: l10n.auth_createAccount,
            isLoading: _isLoading,
            // The checkbox IS the gate — a disabled button needs no error copy.
            onPressed: _consented ? _createAccount : null,
          ),
          if (_codeDied) ...[
            const SizedBox(height: AppSpacing.sp8),
            Center(
              child: TextButton(
                onPressed: _isLoading
                    ? null
                    : () => Navigator.of(context).maybePop(),
                child: Text(l10n.auth_reEnterCode),
              ),
            ),
          ],
          if (bannerSuccess != null) ...[
            const SizedBox(height: AppSpacing.sp8),
            Center(
              child: TextButton(
                onPressed: _backToSignIn,
                child: Text(l10n.auth_backToSignIn),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "You're invited to join as {role}" plus the amber expiry pill. No inviter
/// name — `createEmployeeInvite` stamps none, so there is nothing truthful to
/// render there.
class _InviteBanner extends StatelessWidget {
  const _InviteBanner({required this.preview});

  final InvitePreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final expiresAt = preview.expiresAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sp16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.auth_invitedToJoinAs(
              roleLabel(l10n, isAdmin: preview.isAdmin),
            ),
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
          // A missing expiry renders nothing rather than an epoch date.
          if (expiresAt != null) ...[
            const SizedBox(height: AppSpacing.sp8),
            _ExpiryPill(expiresAt: expiresAt),
          ],
        ],
      ),
    );
  }
}

class _ExpiryPill extends StatelessWidget {
  const _ExpiryPill({required this.expiresAt});

  final DateTime expiresAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = theme.statusColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp12,
        vertical: AppSpacing.sp4,
      ),
      decoration: BoxDecoration(
        color: status.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
      child: Text(
        context.l10n.auth_inviteExpiresOn(
          DateUtilsHelper.formatDate(expiresAt),
        ),
        style: theme.textTheme.labelSmall?.copyWith(
          color: status.onWarningContainer,
        ),
      ),
    );
  }
}

/// The invite email, presented read-only. Deliberately NOT a disabled
/// [TextField]: there is nothing to focus, autofill must not target it, and a
/// disabled field truncates at large text scale where a wrapping [Text] does
/// not.
class _LockedEmailPanel extends StatelessWidget {
  const _LockedEmailPanel({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.palette;
    final l10n = context.l10n;

    return Semantics(
      readOnly: true,
      label: l10n.common_email,
      value: email,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sp16),
        decoration: BoxDecoration(
          color: palette.lockedPanel,
          borderRadius: BorderRadius.circular(AppRadius.r12),
          border: Border.all(color: palette.lockedPanelBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sp8,
              runSpacing: AppSpacing.sp4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.common_email, style: theme.textTheme.labelLarge),
                const _FromInviteChip(),
              ],
            ),
            const SizedBox(height: AppSpacing.sp8),
            Text(
              email,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textBody,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FromInviteChip extends StatelessWidget {
  const _FromInviteChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 12, color: scheme.onPrimaryContainer),
          const SizedBox(width: AppSpacing.sp4),
          Text(
            context.l10n.auth_fromInvite,
            style: theme.monoType.micro.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// One combined terms + location row on its own tinted surface. Unchecked
/// disables the primary button, which is the whole gate.
class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The tint rides `tileColor`, not a wrapping DecoratedBox — a ListTile
    // paints onto the nearest Material, so an outer background would swallow
    // its ink splashes (and asserts in debug).
    return CheckboxListTile.adaptive(
      key: const Key('inviteConsent'),
      value: value,
      activeColor: scheme.primary,
      tileColor: scheme.primaryContainer,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp8,
        vertical: AppSpacing.sp4,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      title: Text(
        context.l10n.auth_termsAndLocationConsent,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
      ),
      onChanged: enabled ? (next) => onChanged(next ?? false) : null,
    );
  }
}
