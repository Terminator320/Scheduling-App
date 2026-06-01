import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/animations/animated_form_field_wrapper.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/features/auth/data/auth_error_mapper.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/screens/create_account_screen.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';

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

      await Navigator.pushReplacementNamed(
        context,
        AppRoutes.mainCalendar,
        arguments: MainCalendarArgs(
          isAdmin: employee.isAdmin,
          employeeId: employee.id,
        ),
      );
    } catch (error) {
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

  Widget _buildBanner(TextTheme textTheme) {
    final scheme = Theme.of(context).colorScheme;
    if (_bannerError != null) {
      return Padding(
        key: ValueKey('err_$_bannerError'),
        padding: const EdgeInsets.only(bottom: AppSpacing.sp12),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sp12),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(AppRadius.r8),
            border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: scheme.error, size: 16),
              const SizedBox(width: AppSpacing.sp8),
              Expanded(
                child: Text(
                  _bannerError!,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_bannerSuccess != null) {
      return Padding(
        key: ValueKey('ok_$_bannerSuccess'),
        padding: const EdgeInsets.only(bottom: AppSpacing.sp12),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sp12),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.r8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                color: scheme.tertiary,
                size: 16,
              ),
              const SizedBox(width: AppSpacing.sp8),
              Expanded(
                child: Text(
                  _bannerSuccess!,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink(key: ValueKey('banner_none'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sp24,
              vertical: AppSpacing.sp32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:
                  [
                        const _LoginLogo(),
                        const SizedBox(height: AppSpacing.sp24),
                        const _LoginHeaderText(),
                        const SizedBox(height: AppSpacing.sp16),
                        AnimatedSwitcher(
                          duration: AppAnimationDurations.banner,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SizeTransition(
                                  sizeFactor: animation,
                                  axisAlignment: -1,
                                  child: child,
                                ),
                              ),
                          child: _buildBanner(textTheme),
                        ),
                        const SizedBox(height: AppSpacing.sp16),
                        _LoginEmailField(
                          controller: _emailController,
                          focusNode: _emailFocus,
                          enabled: !_isLoading,
                          hasError: _emailError != null,
                          errorText: _submitted ? _emailError : null,
                          onSubmitted: () => _passwordFocus.requestFocus(),
                          onChanged: _onFieldChanged,
                        ),
                        const SizedBox(height: AppSpacing.sp16),
                        _LoginPasswordField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          enabled: !_isLoading,
                          hasError: _passwordError != null,
                          errorText: _submitted ? _passwordError : null,
                          isObscured: _isObscured,
                          onSubmitted: _signIn,
                          onChanged: _onFieldChanged,
                          onToggleObscured: () =>
                              setState(() => _isObscured = !_isObscured),
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
                      ]
                      .animate(interval: 65.ms)
                      .fadeIn(duration: 425.ms, curve: Curves.easeOutCubic)
                      .slideY(
                        begin: 0.28,
                        duration: 425.ms,
                        curve: Curves.easeOutCubic,
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginLogo extends StatelessWidget {
  const _LoginLogo();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Icon(
        Icons.calendar_today_rounded,
        color: scheme.onPrimary,
        size: 22,
      ),
    );
  }
}

class _LoginHeaderText extends StatelessWidget {
  const _LoginHeaderText();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.auth_welcomeBack, style: textTheme.headlineLarge),
        const SizedBox(height: 4),
        Text(
          context.l10n.auth_signInToYourAccount,
          style: textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _LoginEmailField extends StatelessWidget {
  const _LoginEmailField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hasError,
    required this.errorText,
    required this.onSubmitted,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool hasError;
  final String? errorText;
  final VoidCallback onSubmitted;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedFormFieldWrapper(
      hasError: hasError,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.email],
        enabled: enabled,
        onSubmitted: (_) => onSubmitted(),
        onChanged: (_) => onChanged(),
        decoration: formInputDecoration(context, context.l10n.common_email)
            .copyWith(
              errorText: errorText,
              prefixIcon: const Icon(Icons.email_outlined, size: 20),
            ),
      ),
    );
  }
}

class _LoginPasswordField extends StatelessWidget {
  const _LoginPasswordField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hasError,
    required this.errorText,
    required this.isObscured,
    required this.onSubmitted,
    required this.onChanged,
    required this.onToggleObscured,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool hasError;
  final String? errorText;
  final bool isObscured;
  final VoidCallback onSubmitted;
  final VoidCallback onChanged;
  final VoidCallback onToggleObscured;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedFormFieldWrapper(
      hasError: hasError,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: isObscured,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        enabled: enabled,
        onSubmitted: (_) => onSubmitted(),
        onChanged: (_) => onChanged(),
        decoration: formInputDecoration(context, context.l10n.common_password)
            .copyWith(
              errorText: errorText,
              prefixIcon: const Icon(Icons.lock_outlined, size: 20),
              suffixIcon: AnimatedSwitcher(
                duration: AppAnimationDurations.quick,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.7, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: IconButton(
                  key: ValueKey(isObscured),
                  icon: Icon(
                    isObscured
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  tooltip: isObscured
                      ? context.l10n.auth_showPassword
                      : context.l10n.auth_hidePassword,
                  onPressed: onToggleObscured,
                ),
              ),
            ),
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
