import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
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
import 'package:scheduling/features/employees/domain/policies/starting_password_policy.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/primitives/busy_button_icon.dart';

/// First-run setup for an employee whose account an admin created.
///
/// They are ALREADY signed in when they get here — with the shared starting
/// password — and their `users` doc is still `invited`, which is what withholds
/// every rules grant. This screen is the only route out of that state: it
/// replaces the password and then activates the account, in that order (see
/// [AuthService.completeAccountSetup] for why the order is the guarantee).
///
/// The email is NOT asked for and NOT editable — it is the address they just
/// signed in with, so it is rendered locked.
class AccountSetupScreen extends ConsumerStatefulWidget {
  const AccountSetupScreen({
    this.firstName = '',
    this.lastName = '',
    this.authService,
    super.key,
  });

  /// Whatever the admin already typed, so the person confirms rather than
  /// retypes. Blank is fine — the fields are still required.
  final String firstName;
  final String lastName;
  final AuthService? authService;

  @override
  ConsumerState<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends ConsumerState<AccountSetupScreen> {
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

  /// The second gate beside consent. The account was minted on a password
  /// every admin knows, so verification is the only thing that proves the
  /// person on this screen owns the mailbox — and the server refuses to
  /// activate without it.
  late bool _emailVerified;
  bool _isSendingVerification = false;
  bool _isCheckingVerification = false;
  bool _verificationSent = false;
  String? _verificationNotice;

  String? _firstNameError;
  String? _lastNameError;
  String? _passwordError;
  String? _confirmError;
  String? _bannerError;
  String? _bannerSuccess;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.firstName);
    _lastNameController = TextEditingController(text: widget.lastName);
    _emailVerified = _authService.isEmailVerified;
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
    //
    // The shared starting password satisfies every one of those requirements,
    // so it has to be rejected by name: without this, someone can "set" their
    // password to the value the admin just read out and end up permanently
    // `active` on a constant that is in the source, on every pending roster row
    // and known to every admin. Replacing it is the whole reason this screen
    // is reachable, and the only thing that closes the onboarding window.
    //
    // Validated TRIMMED, because `completeAccountSetup` stores the trimmed
    // value: checking `"Aa1!bcd "` (8) and then setting `"Aa1!bcd"` (7) let a
    // password through that does not meet the policy it was checked against.
    final password = _passwordController.text.trim();
    final passwordErr =
        AuthValidators.newPassword(context, password) ??
        (password == kDefaultStartingPassword
            ? l10n.validation_passwordMustDifferFromStarting
            : null);

    String? confirmErr;
    if (_confirmController.text.trim().isEmpty) {
      confirmErr = l10n.validation_pleaseConfirmYourPassword;
    } else if (_confirmController.text.trim() !=
        _passwordController.text.trim()) {
      confirmErr = l10n.validation_passwordsDoNotMatch;
    }

    // Only rebuild when a message actually changed: after the first failed
    // submit this runs on EVERY keystroke in EVERY field, and an unconditional
    // setState there rebuilds the whole form to redraw identical error text.
    if (firstErr != _firstNameError ||
        lastErr != _lastNameError ||
        passwordErr != _passwordError ||
        confirmErr != _confirmError) {
      setState(() {
        _firstNameError = firstErr;
        _lastNameError = lastErr;
        _passwordError = passwordErr;
        _confirmError = confirmErr;
      });
    }

    return firstErr == null &&
        lastErr == null &&
        passwordErr == null &&
        confirmErr == null;
  }

  void _onFieldChanged() {
    if (_submitted) _validate();
    if (_bannerError != null) setState(() => _bannerError = null);
  }

  /// No `setState` here: the meter and the checklist listen to the controller
  /// directly (see `_passwordFeedback`), so a keystroke repaints those two
  /// widgets instead of rebuilding all five fields, the consent row and the
  /// submit button.
  void _onPasswordChanged() => _onFieldChanged();

  /// Sends Firebase's own verification email to the address they signed in
  /// with. Deliberately user-triggered rather than automatic: an auto-send on
  /// every visit spends the provider's rate limit on people who already have
  /// the message open.
  Future<void> _sendVerificationEmail() async {
    if (_isSendingVerification) return;
    setState(() {
      _isSendingVerification = true;
      _verificationNotice = null;
      _bannerError = null;
    });
    try {
      await _authService.sendVerificationEmail();
      if (!mounted) return;
      setState(() {
        _isSendingVerification = false;
        _verificationSent = true;
        _verificationNotice = context.l10n.auth_verificationEmailSent;
      });
    } catch (error, stackTrace) {
      final failure = AuthErrorMapper.map(error);
      ref
          .read(loggerProvider)
          .authFailure(
            'AUTH-SETUP sendVerificationEmail failed',
            failure,
            error,
            stackTrace,
          );
      if (!mounted) return;
      setState(() {
        _isSendingVerification = false;
        _bannerError = failure.toLocalizedMessageInContext(
          context,
          AuthErrorContext.register,
        );
      });
    }
  }

  /// Re-reads the account after they have opened the link.
  ///
  /// [AuthService.refreshEmailVerified] also forces a token refresh — the
  /// callable reads `email_verified` off the token, so without that the server
  /// would keep refusing an address the person has already verified.
  Future<void> _checkVerification() async {
    if (_isCheckingVerification) return;
    setState(() {
      _isCheckingVerification = true;
      _verificationNotice = null;
      _bannerError = null;
    });
    try {
      final verified = await _authService.refreshEmailVerified();
      if (!mounted) return;
      setState(() {
        _isCheckingVerification = false;
        _emailVerified = verified;
        _verificationNotice = verified
            ? null
            : context.l10n.auth_emailNotVerifiedYet;
      });
    } catch (error, stackTrace) {
      final failure = AuthErrorMapper.map(error);
      ref
          .read(loggerProvider)
          .authFailure(
            'AUTH-SETUP refreshEmailVerified failed',
            failure,
            error,
            stackTrace,
          );
      if (!mounted) return;
      setState(() {
        _isCheckingVerification = false;
        _bannerError = failure.toLocalizedMessageInContext(
          context,
          AuthErrorContext.register,
        );
      });
    }
  }

  Future<void> _finishSetup() async {
    // Reentrancy guard, synchronously first: AnimatedLoadingButton only nulls
    // onPressed after the setState rebuild, so a same-frame double-tap would
    // otherwise run two updatePassword calls and two completeEmployeeSetup
    // invocations — burning 2 of 5 rate-limit slots and pushing the hub twice.
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    // Consent and email verification are the two gates, and this is where they
    // are enforced: the confirm-password field's keyboard-submit reaches here
    // without consulting the disabled button, so gating only at the CTA would
    // let Done through. Verification is also the SERVER's gate, so submitting
    // without it can only produce a failure notice.
    if (!_consented || !_emailVerified) return;

    setState(() {
      _submitted = true;
      _bannerError = null;
    });

    if (!_validate()) return;

    // Before the in-flight flag: an awaited write offline never resolves until
    // the connection returns, so the button would just spin.
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
      await _authService.completeAccountSetup(
        newPassword: _passwordController.text,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
        termsAccepted: _consented,
        locationConsent: _consented,
      );
      // Success only — a failed attempt must never ask the OS to save it.
      TextInput.finishAutofillContext();
      if (!mounted) return;
      await _routeIntoApp();
    } catch (error, stackTrace) {
      final failure = AuthErrorMapper.map(error);
      ref
          .read(loggerProvider)
          .authFailure(
            'AUTH-SETUP completeAccountSetup failed',
            failure,
            error,
            stackTrace,
          );
      if (!mounted) return;
      // Already active: the password change that precedes activation DID land,
      // so this person is finished, not stuck. Walk them in rather than
      // reporting a failure they cannot act on.
      if (failure is AuthFailureSetupAlreadyComplete) {
        await _routeIntoApp();
        return;
      }
      setState(() {
        _isLoading = false;
        // The local flag said verified but the token did not carry the claim,
        // so put the step back rather than leaving a CTA that can only fail.
        if (failure is AuthFailureEmailNotVerified) _emailVerified = false;
        _bannerError = failure.toLocalizedMessageInContext(
          context,
          AuthErrorContext.register,
        );
      });
    }
  }

  /// Setup leaves us signed in and now active, so resolve the freshly
  /// activated profile and go straight into the app.
  Future<void> _routeIntoApp() async {
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
      // The account is active server-side; the doc just isn't readable yet.
      // Say so and offer the way back to sign-in.
      case SignInNoSession() || SignInProfilePending():
        setState(() {
          _isLoading = false;
          _bannerSuccess = context.l10n.auth_accountReadySignInAgain;
        });
      // These only come from signIn() — resumeAfterSignUp() never produces
      // them, but the sealed family forces the branch. `NeedsAccountSetup`
      // included: reaching it here would mean activation didn't stick, and
      // looping back onto this same screen is not a recovery.
      case SignInInvalidCredentials() ||
          SignInNoProfile() ||
          SignInAccountDisabled() ||
          SignInNeedsAccountSetup() ||
          SignInError():
        break;
    }
  }

  /// Abandoning setup has to be possible: the person is holding a live session
  /// on an account that can read nothing, and the only way back to the sign-in
  /// screen is to drop it.
  ///
  /// A plain `signOut`, deliberately — NOT the `AccountExitListeners` teardown
  /// the Settings sign-out runs first. That order is load-bearing because push,
  /// presence and Live Activity de-registration each need the credential
  /// sign-out revokes; an `invited` account has none of those registrations to
  /// begin with (the rules deny it every collection they write to), so there is
  /// nothing to tear down. If a future registration ever starts before
  /// activation, this has to route through the shared exit path instead.
  Future<void> _signOut() async {
    await _authService.signOut();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final bannerSuccess = _bannerSuccess;
    final email = _authService.currentUser?.email ?? '';

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.auth_setUpYourAccountTitle,
            style: theme.textTheme.headlineLarge,
          ),
          const SizedBox(height: AppSpacing.sp16),
          const _SetupBanner(),
          if (email.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sp16),
            _LockedEmailPanel(email: email, isVerified: _emailVerified),
          ],
          if (!_emailVerified) ...[
            const SizedBox(height: AppSpacing.sp16),
            _VerifyEmailPanel(
              hasSent: _verificationSent,
              isSending: _isSendingVerification,
              isChecking: _isCheckingVerification,
              notice: _verificationNotice,
              onSend: _sendVerificationEmail,
              onCheck: _checkVerification,
            ),
          ],
          const SizedBox(height: AppSpacing.sp16),
          LabeledTextField(
            key: const Key('firstName'),
            label: l10n.employees_firstName,
            controller: _firstNameController,
            required: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.givenName],
            maxLength: TextLimits.employeeNameHalf,
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
            maxLength: TextLimits.employeeNameHalf,
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
            label: l10n.auth_newPassword,
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
          _passwordFeedback(),
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
            onSubmitted: _finishSetup,
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
            label: l10n.auth_finishSetup,
            isLoading: _isLoading,
            // The checkbox and the verification panel ARE the gates — both are
            // on screen and self-explanatory, so a disabled button needs no
            // error copy of its own.
            onPressed: _consented && _emailVerified ? _finishSetup : null,
          ),
          const SizedBox(height: AppSpacing.sp8),
          Center(
            child: TextButton(
              onPressed: _isLoading ? null : _signOut,
              child: Text(l10n.settings_logOut),
            ),
          ),
        ],
      ),
    );
  }

  /// The strength meter and the requirements checklist, rebuilt from the
  /// controller rather than from screen state.
  ///
  /// These two are the only things on the form that track the password on
  /// every keystroke, and `TextEditingController` is already a
  /// `ValueListenable` — so scoping the listen here keeps a keypress from
  /// rebuilding the five fields, the consent row and the submit button around
  /// them.
  Widget _passwordFeedback() => ValueListenableBuilder<TextEditingValue>(
    valueListenable: _passwordController,
    builder: (context, value, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sp8),
        // Trimmed, so the meter and the checklist judge the same string
        // `_validate` gates on and `completeAccountSetup` stores.
        PasswordStrengthMeter(password: value.text.trim()),
        const SizedBox(height: AppSpacing.sp8),
        PasswordRequirementsChecklist(password: value.text.trim()),
      ],
    ),
  );
}

/// Explains why this screen exists at all: they signed in with a password
/// somebody else chose, and it stops working the moment they finish here.
class _SetupBanner extends StatelessWidget {
  const _SetupBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sp16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Text(
        context.l10n.auth_setUpYourAccountBody,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// The sign-in email, presented read-only. Deliberately NOT a disabled
/// [TextField]: there is nothing to focus, autofill must not target it, and a
/// disabled field truncates at large text scale where a wrapping [Text] does
/// not.
class _LockedEmailPanel extends StatelessWidget {
  const _LockedEmailPanel({required this.email, required this.isVerified});

  final String email;
  final bool isVerified;

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
                _SignedInChip(isVerified: isVerified),
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

/// Reads SIGNED IN until the address is verified, then VERIFIED. The icon
/// changes with the label, so the state is never signalled by colour alone.
class _SignedInChip extends StatelessWidget {
  const _SignedInChip({required this.isVerified});

  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.statusColors;
    final background = isVerified
        ? status.successContainer
        : scheme.primaryContainer;
    final foreground = isVerified
        ? status.onSuccessContainer
        : scheme.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVerified ? Icons.verified_outlined : Icons.lock_outline,
            size: 12,
            color: foreground,
          ),
          const SizedBox(width: AppSpacing.sp4),
          Text(
            isVerified
                ? context.l10n.auth_emailVerified
                : context.l10n.auth_signedInAs,
            style: theme.monoType.micro.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

/// The email-verification step: send the link, then confirm it was opened.
///
/// This is a real gate, not a nudge — `completeEmployeeSetup` refuses without
/// `email_verified`, because the account was created on a password every admin
/// knows and control of the mailbox is the only thing that identifies the
/// person on this screen.
class _VerifyEmailPanel extends StatelessWidget {
  const _VerifyEmailPanel({
    required this.hasSent,
    required this.isSending,
    required this.isChecking,
    required this.notice,
    required this.onSend,
    required this.onCheck,
  });

  final bool hasSent;
  final bool isSending;
  final bool isChecking;
  final String? notice;
  final VoidCallback onSend;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final message = notice;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sp16),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.mark_email_unread_outlined,
                size: 18,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: AppSpacing.sp8),
              Expanded(
                child: Text(
                  l10n.auth_verifyEmailTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sp8),
          Text(
            l10n.auth_verifyEmailBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onTertiaryContainer,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.sp8),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sp12),
          // Wrap, not Row: at large text scales the two labels are long enough
          // to overflow side by side.
          Wrap(
            spacing: AppSpacing.sp8,
            runSpacing: AppSpacing.sp8,
            children: [
              FilledButton.tonalIcon(
                key: const Key('sendVerificationEmail'),
                onPressed: isSending ? null : onSend,
                icon: BusyButtonIcon(
                  isBusy: isSending,
                  icon: Icons.send_outlined,
                ),
                label: Text(
                  hasSent
                      ? l10n.auth_resendVerificationEmail
                      : l10n.auth_sendVerificationEmail,
                ),
              ),
              OutlinedButton.icon(
                key: const Key('checkVerification'),
                onPressed: isChecking ? null : onCheck,
                icon: BusyButtonIcon(
                  isBusy: isChecking,
                  icon: Icons.refresh,
                ),
                label: Text(l10n.auth_checkVerification),
              ),
            ],
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
      key: const Key('setupConsent'),
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
