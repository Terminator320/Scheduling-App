import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/animations/animated_form_field_wrapper.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/animations/fade_slide_entrance.dart';
import 'package:scheduling/core/animations/staggered_entrance_controller.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/features/auth/data/auth_error_mapper.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/screens/create_account_screen.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';

class Login extends ConsumerStatefulWidget {
  const Login({super.key});

  @override
  ConsumerState<Login> createState() => _LoginState();
}

class _LoginState extends ConsumerState<Login>
    with SingleTickerProviderStateMixin {
  static const int _itemCount = 7;

  final AuthService _authService = AuthService();
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

  late final StaggeredEntranceController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = StaggeredEntranceController(vsync: this, itemCount: _itemCount)
      ..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
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
    // Only re-validate on every keystroke after the first submit attempt,
    // so errors don't flash before the user has had a chance to fill the form.
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
          _bannerError = context.l10n.invalidEmailOrPassword;
          _isLoading = false;
        });
        return;
      }

      final userDoc = await ref
          .read(employeesRepositoryProvider)
          .findUserByUid(user.uid);
      if (!mounted) return;

      if (userDoc == null) {
        setState(() {
          _bannerError = context.l10n.noUserProfileFoundForThisAccount;
          _isLoading = false;
        });
        return;
      }

      final employee = EmployeeRecord.fromMap(userDoc.id, userDoc.data);

      if (employee.isDisabled) {
        await _authService.signOut();
        if (!mounted) return;
        setState(() {
          _bannerError = context.l10n.thisAccountHasBeenDisabled;
          _isLoading = false;
        });
        return;
      }

      unawaited(AuthCache().save(employee));

      Navigator.pushReplacementNamed(
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
        builder: (_) => CreateAccountScreen(
          initialEmail: prefill.isEmpty ? null : prefill,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {
      _submitted = false;
      _emailError = null;
      _passwordError = null;
      _bannerError = null;
      _bannerSuccess = result?.created ?? false
          ? context.l10n.accountCreatedYouCanNowSignIn
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
    final animations = _entrance.animations;

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
              children: [
                // Logo
                FadeSlideEntrance(
                  animation: animations[0],
                  child: Container(
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
                  ),
                ),
                const SizedBox(height: AppSpacing.sp24),
                FadeSlideEntrance(
                  animation: animations[1],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.welcomeBack,
                        style: textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.signInToYourAccount,
                        style: textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sp16),
                AnimatedSwitcher(
                  duration: AppAnimationDurations.banner,
                  transitionBuilder: (child, animation) => FadeTransition(
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
                // Email field
                FadeSlideEntrance(
                  animation: animations[2],
                  child: AnimatedFormFieldWrapper(
                    hasError: _emailError != null,
                    child: TextField(
                      controller: _emailController,
                      focusNode: _emailFocus,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.email],
                      enabled: !_isLoading,
                      onSubmitted: (_) => _passwordFocus.requestFocus(),
                      onChanged: (_) => _onFieldChanged(),
                      decoration: formInputDecoration(
                        context,
                        context.l10n.email,
                      ).copyWith(
                        errorText: _submitted ? _emailError : null,
                        prefixIcon: const Icon(
                          Icons.email_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sp16),
                // Password field
                FadeSlideEntrance(
                  animation: animations[3],
                  child: AnimatedFormFieldWrapper(
                    hasError: _passwordError != null,
                    child: TextField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      obscureText: _isObscured,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      enabled: !_isLoading,
                      onSubmitted: (_) => _signIn(),
                      onChanged: (_) => _onFieldChanged(),
                      decoration: formInputDecoration(
                        context,
                        context.l10n.password,
                      ).copyWith(
                        errorText: _submitted ? _passwordError : null,
                        prefixIcon: const Icon(
                          Icons.lock_outlined,
                          size: 20,
                        ),
                        suffixIcon: AnimatedSwitcher(
                          duration: AppAnimationDurations.quick,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: 0.7,
                                    end: 1,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: IconButton(
                            key: ValueKey(_isObscured),
                            icon: Icon(
                              _isObscured
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                            tooltip: _isObscured
                                ? context.l10n.showPassword
                                : context.l10n.hidePassword,
                            onPressed: () =>
                                setState(() => _isObscured = !_isObscured),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sp24),
                // Sign In button
                FadeSlideEntrance(
                  animation: animations[5],
                  child: AnimatedLoadingButton(
                    label: context.l10n.signIn,
                    isLoading: _isLoading,
                    onPressed: _signIn,
                  ),
                ),
                const SizedBox(height: AppSpacing.sp16),
                // Bottom links row
                FadeSlideEntrance(
                  animation: animations[6],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _isLoading ? null : _openForgotPassword,
                        child: Text(
                          context.l10n.forgotPassword3,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _isLoading ? null : _openCreateAccount,
                        child: Text(
                          context.l10n.createAccount,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
