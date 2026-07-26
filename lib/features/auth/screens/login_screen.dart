import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/storage/secure_storage_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/features/auth/application/sign_in_controller.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/screens/create_account_screen.dart';
import 'package:scheduling/features/auth/widgets/auth_banner.dart';
import 'package:scheduling/features/auth/widgets/auth_form_widgets.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';

class Login extends ConsumerStatefulWidget {
  const Login({super.key});

  @override
  ConsumerState<Login> createState() => _LoginState();
}

class _LoginState extends ConsumerState<Login> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _isObscured = true;
  bool _submitted = false;

  String? _emailError;
  String? _passwordError;
  String? _bannerError;
  String? _bannerSuccess;

  @override
  void initState() {
    super.initState();
    _prefillRememberedEmail();
  }

  Future<void> _prefillRememberedEmail() async {
    try {
      final email = await ref
          .read(secureStorageServiceProvider)
          .read(SecureStorageKeys.rememberedEmail);
      if (!mounted || email == null || email.isEmpty) return;
      if (_emailController.text.isNotEmpty) return;
      _emailController.text = email;
    } catch (e, st) {
      if (mounted) ref.read(loggerProvider).warn('login.prefill_email', e, st);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool _validate() {
    final emailErr = AuthValidators.email(context, _emailController.text);
    final passwordErr = AuthValidators.password(
      context,
      _passwordController.text,
    );

    setState(() {
      _emailError = emailErr;
      _passwordError = passwordErr;
    });

    return emailErr == null && passwordErr == null;
  }

  void _onFieldChanged() {
    if (_submitted) _validate();
    if (_bannerError != null || _bannerSuccess != null) {
      setState(() {
        _bannerError = null;
        _bannerSuccess = null;
      });
    }
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _submitted = true;
      _bannerError = null;
      _bannerSuccess = null;
    });

    if (!_validate()) return;

    final outcome = await ref
        .read(signInControllerProvider.notifier)
        .signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
    if (!mounted) return;

    switch (outcome) {
      case SignInSuccess(:final employee):
        TextInput.finishAutofillContext(); // Offer to save these credentials in the OS password manager.
        await _routeToCalendar(employee);
      case SignInInvalidCredentials():
        setState(() {
          _bannerError = context.l10n.error_invalidEmailOrPassword;
        });
      case SignInNoProfile():
        setState(() {
          _bannerError = context.l10n.error_noUserProfileFoundForThisAccount;
        });
      case SignInAccountDisabled():
        setState(() {
          _bannerError = context.l10n.error_thisAccountHasBeenDisabled;
        });
      case SignInError(:final failure):
        setState(() {
          _bannerError = failure.toLocalizedMessageInContext(
            context,
            AuthErrorContext.login,
          );
        });
      // These only come from resumeAfterSignUp() — signIn() never produces them.
      case SignInNoSession() || SignInProfilePending():
        break;
    }
  }

  Future<void> _openCreateAccount() async {
    final prefill = _emailController.text.trim();
    final result = await Navigator.of(context).push<CreateAccountResult>(
      MaterialPageRoute(
        builder: (_) =>
            CreateAccountScreen(initialEmail: prefill.isEmpty ? null : prefill),
      ),
    );

    if (!mounted) return;

    if (result?.created == true) {
      await _routeAfterSignUp();
      return;
    }

    setState(() {
      _submitted = false;
      _emailError = null;
      _passwordError = null;
      _bannerError = null;
      _bannerSuccess = null;
    });
  }

  Future<void> _routeToCalendar(EmployeeRecord employee) async {
    await Navigator.pushReplacementNamed(
      context,
      AppRoutes.mainCalendar,
      arguments: MainCalendarArgs(
        isAdmin: employee.isAdmin,
        employeeId: employee.id,
      ),
    );
  }

  // Create-account leaves us with an authenticated session, so resolve the
  // profile and route straight into the app.
  Future<void> _routeAfterSignUp() async {
    final outcome = await ref
        .read(signInControllerProvider.notifier)
        .resumeAfterSignUp();
    if (!mounted) return;
    switch (outcome) {
      case SignInNoSession():
        return;
      case SignInProfilePending():
        setState(() {
          _bannerSuccess = context.l10n.auth_accountCreatedYouCanNowSignIn;
        });
      case SignInSuccess(:final employee):
        TextInput.finishAutofillContext();
        await _routeToCalendar(employee);
      // These only come from signIn() — resumeAfterSignUp() never produces them.
      case SignInInvalidCredentials() ||
          SignInNoProfile() ||
          SignInAccountDisabled() ||
          SignInError():
        break;
    }
  }

  Future<void> _openForgotPassword() async {
    final prefill = _emailController.text.trim();
    await Navigator.pushNamed(
      context,
      AppRoutes.forgotPassword,
      arguments: ForgotPasswordArgs(
        initialEmail: prefill.isEmpty ? null : prefill,
      ),
    );
    if (!mounted) return;
    setState(() {
      _submitted = false;
      _emailError = null;
      _passwordError = null;
      _bannerError = null;
      _bannerSuccess = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(signInControllerProvider).inProgress;
    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthBrandHeader(
            title: context.l10n.auth_welcomeBack,
            subtitle: context.l10n.auth_signInToYourAccount,
          ),
          const SizedBox(height: AppSpacing.sp24),
          AuthBanner(
            message: _bannerError ?? _bannerSuccess,
            kind: _bannerError != null
                ? AuthBannerKind.error
                : AuthBannerKind.success,
          ),
          const SizedBox(height: AppSpacing.sp16),
          AuthEmailField(
            controller: _emailController,
            focusNode: _emailFocus,
            enabled: !isLoading,
            hasError: _emailError != null,
            errorText: _submitted ? _emailError : null,
            onSubmitted: _passwordFocus.requestFocus,
            onChanged: _onFieldChanged,
          ),
          const SizedBox(height: AppSpacing.sp16),
          AuthPasswordField(
            label: context.l10n.common_password,
            controller: _passwordController,
            focusNode: _passwordFocus,
            enabled: !isLoading,
            hasError: _passwordError != null,
            errorText: _submitted ? _passwordError : null,
            isObscured: _isObscured,
            onSubmitted: _signIn,
            onChanged: _onFieldChanged,
            onToggleObscured: () => setState(() => _isObscured = !_isObscured),
          ),
          const SizedBox(height: AppSpacing.sp8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: isLoading ? null : _openForgotPassword,
              child: Text(context.l10n.auth_forgotPassword),
            ),
          ),
          const SizedBox(height: AppSpacing.sp8),
          AnimatedLoadingButton(
            label: context.l10n.auth_signIn,
            isLoading: isLoading,
            onPressed: _signIn,
          ),
          const SizedBox(height: AppSpacing.sp24),
          _CreateAccountPrompt(
            enabled: !isLoading,
            onCreateAccount: _openCreateAccount,
          ),
        ],
      ),
    );
  }
}

/// The bottom CTA on the sign-in screen — a muted prompt plus a "Create account"
/// link, wrapped so it still flows nicely at large text scale.
class _CreateAccountPrompt extends StatelessWidget {
  const _CreateAccountPrompt({
    required this.enabled,
    required this.onCreateAccount,
  });

  final bool enabled;
  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          context.l10n.auth_dontHaveAnAccount,
          style: textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        TextButton(
          onPressed: enabled ? onCreateAccount : null,
          child: Text(
            context.l10n.auth_createAccount,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
