import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/storage/secure_storage_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/auth/data/auth_error_mapper.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/screens/create_account_screen.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/auth/widgets/auth_banner.dart';
import 'package:scheduling/features/auth/widgets/auth_form_widgets.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';

class Login extends ConsumerStatefulWidget {
  const Login({super.key, this.authService});

  final AuthService? authService;

  @override
  ConsumerState<Login> createState() => _LoginState();
}

class _LoginState extends ConsumerState<Login> {
  late final AuthService _authService = widget.authService ?? AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _isObscured = true;
  bool _isLoading = false;
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

    setState(() => _isLoading = true);

    try {
      final credential = await _authService.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );

      final user = credential.user;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _bannerError = context.l10n.error_invalidEmailOrPassword;
          _isLoading = false;
        });
        return;
      }

      // Reload to pick up email_verified status, then auto-activate the
      // invite if the user has verified their email since registering.
      await _authService.tryActivateInvitedEmployee(user);

      final userDoc = await ref
          .read(employeesRepositoryProvider)
          .findUserByUid(user.uid);
      if (!mounted) return;

      if (userDoc == null) {
        await _authService.signOut();
        if (!mounted) return;
        setState(() {
          _bannerError = (user.emailVerified)
              ? context.l10n.error_noUserProfileFoundForThisAccount
              : context.l10n.auth_pleaseVerifyYourEmailBeforeSigningIn;
          _isLoading = false;
        });
        return;
      }

      final employee = EmployeeRecord.fromMap(userDoc.id, userDoc.data);

      if (!employee.isActive) {
        await _authService.signOut();
        if (!mounted) return;
        setState(() {
          _bannerError = context.l10n.error_thisAccountHasBeenDisabled;
          _isLoading = false;
        });
        return;
      }

      unawaited(
        AuthCache().save(employee).catchError((Object e, StackTrace st) {
          ref.read(loggerProvider).warn('login.auth_cache_save', e, st);
        }),
      );

      unawaited(
        ref
            .read(secureStorageServiceProvider)
            .write(
              SecureStorageKeys.rememberedEmail,
              _emailController.text.trim().toLowerCase(),
            )
            .catchError((Object e, StackTrace st) {
              ref.read(loggerProvider).warn('login.remember_email', e, st);
            }),
      );

      await Navigator.pushReplacementNamed(
        context,
        AppRoutes.mainCalendar,
        arguments: MainCalendarArgs(
          isAdmin: employee.isAdmin,
          employeeId: employee.id,
        ),
      );
    } catch (error, stackTrace) {
      ref.read(loggerProvider).warn('login.sign_in', error, stackTrace);
      if (!mounted) return;
      final failure = AuthErrorMapper.map(error);
      setState(() {
        _bannerError = failure.toLocalizedMessageInContext(
          context,
          AuthErrorContext.login,
        );
        _isLoading = false;
      });
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

    setState(() {
      _submitted = false;
      _emailError = null;
      _passwordError = null;
      _bannerError = null;
      _bannerSuccess = result?.created ?? false
          ? context.l10n.auth_accountCreatedYouCanNowSignIn
          : null;
    });

    if (result?.email != null && result!.email!.trim().isNotEmpty) {
      _emailController.text = result.email!.trim().toLowerCase();
      _passwordController.clear();
      _passwordFocus.requestFocus();
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
    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AuthLogo(),
          const SizedBox(height: AppSpacing.sp24),
          AuthHeaderText(
            title: context.l10n.auth_welcomeBack,
            subtitle: context.l10n.auth_signInToYourAccount,
          ),
          const SizedBox(height: AppSpacing.sp16),
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
            enabled: !_isLoading,
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
            enabled: !_isLoading,
            hasError: _passwordError != null,
            errorText: _submitted ? _passwordError : null,
            isObscured: _isObscured,
            onSubmitted: _signIn,
            onChanged: _onFieldChanged,
            onToggleObscured: () => setState(() => _isObscured = !_isObscured),
          ),
          const SizedBox(height: AppSpacing.sp24),
          AnimatedLoadingButton(
            label: context.l10n.auth_signIn,
            isLoading: _isLoading,
            onPressed: _signIn,
          ),
          const SizedBox(height: AppSpacing.sp16),
          _LoginFooterActions(
            enabled: !_isLoading,
            onForgotPassword: _openForgotPassword,
            onCreateAccount: _openCreateAccount,
          ),
        ].authStaggerIn(),
      ),
    );
  }
}

class _LoginFooterActions extends StatelessWidget {
  const _LoginFooterActions({
    required this.enabled,
    required this.onForgotPassword,
    required this.onCreateAccount,
  });

  final bool enabled;
  final VoidCallback onForgotPassword;
  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    // Wrap so the two action labels can flow to a second line
    // at 1.4× / 2.0× text scale instead of overflowing the row.
    // alignment: spaceBetween keeps the original single-line
    // visual at normal scale.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          onPressed: enabled ? onForgotPassword : null,
          child: Text(
            context.l10n.auth_forgotPassword,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        TextButton(
          onPressed: enabled ? onCreateAccount : null,
          child: Text(
            context.l10n.auth_createAccount,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
