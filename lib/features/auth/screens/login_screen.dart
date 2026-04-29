import 'package:flutter/material.dart';

import 'package:scheduling/core/animations/animated_form_field_wrapper.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/animations/fade_slide_entrance.dart';
import 'package:scheduling/core/animations/staggered_entrance_controller.dart';
import 'package:scheduling/core/errors/auth_error_handler.dart';
import 'package:scheduling/core/utils/app_text.dart';
import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/features/auth/screens/create_account_screen.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/auth/widgets/auth_banner.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/features/employees/services/user_service.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> with SingleTickerProviderStateMixin {
  static const int _itemCount = 7;

  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
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
          _bannerError = tr(context, 'Invalid email or password');
          _isLoading = false;
        });
        return;
      }

      final userDoc = await _userService.findUserByUid(user.uid);
      if (!mounted) return;

      if (userDoc == null || !userDoc.exists) {
        setState(() {
          _bannerError = tr(context, 'No user profile found for this account');
          _isLoading = false;
        });
        return;
      }

      final employee = EmployeeRecord.fromMap(userDoc.id, userDoc.data());

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
      setState(() {
        _bannerError = AuthErrorHandler.getMessage(
          context,
          error,
          authContext: AuthErrorContext.login,
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
      _bannerSuccess = result?.created == true
          ? tr(context, 'Account created. You can now sign in.')
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
    final colour = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final safeArea = MediaQuery.of(context).padding;
    final animations = _entrance.animations;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 400,
                  minHeight:
                      MediaQuery.of(context).size.height -
                      safeArea.top -
                      safeArea.bottom,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 28),
                      ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.82,
                          end: 1,
                        ).animate(animations[0]),
                        child: FadeTransition(
                          opacity: animations[0],
                          child: Center(
                            child: Image.asset(
                              'assets/images/logo1.png',
                              height: 120,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FadeSlideEntrance(
                        animation: animations[1],
                        child: Column(
                          children: [
                            Text(
                              tr(context, 'Sign In'),
                              textAlign: TextAlign.center,
                              style: textTheme.headlineLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tr(context, 'Enter email and password'),
                              textAlign: TextAlign.center,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colour.onSurface.withAlpha(150),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 36),
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
                            decoration: formInputDecoration(context, 'Email')
                                .copyWith(
                                  errorText: _emailError,
                                  prefixIcon: const Icon(
                                    Icons.email_outlined,
                                    size: 20,
                                  ),
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
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
                            decoration: formInputDecoration(context, 'Password')
                                .copyWith(
                                  errorText: _passwordError,
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
                                      ),
                                      tooltip: _isObscured
                                          ? tr(context, 'Show password')
                                          : tr(context, 'Hide password'),
                                      onPressed: () => setState(
                                        () => _isObscured = !_isObscured,
                                      ),
                                    ),
                                  ),
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      FadeSlideEntrance(
                        animation: animations[4],
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isLoading ? null : _openForgotPassword,
                            child: Text(
                              tr(context, 'Forgot Password?'),
                              style: textTheme.bodySmall?.copyWith(
                                color: colour.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
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
                        child: _bannerError != null
                            ? Padding(
                                key: ValueKey('err_$_bannerError'),
                                padding: const EdgeInsets.only(bottom: 14),
                                child: AuthBanner(
                                  kind: AuthBannerKind.error,
                                  message: _bannerError!,
                                ),
                              )
                            : _bannerSuccess != null
                            ? Padding(
                                key: ValueKey('ok_$_bannerSuccess'),
                                padding: const EdgeInsets.only(bottom: 14),
                                child: AuthBanner(
                                  kind: AuthBannerKind.success,
                                  message: _bannerSuccess!,
                                ),
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('banner_none'),
                              ),
                      ),
                      FadeSlideEntrance(
                        animation: animations[5],
                        child: AnimatedLoadingButton(
                          label: tr(context, 'Sign In'),
                          isLoading: _isLoading,
                          onPressed: _signIn,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FadeSlideEntrance(
                        animation: animations[6],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Expanded(child: Divider()),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Text(
                                    tr(context, 'or'),
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colour.onSurface.withAlpha(100),
                                    ),
                                  ),
                                ),
                                const Expanded(child: Divider()),
                              ],
                            ),
                            const SizedBox(height: 24),
                            AnimatedLoadingButton(
                              label: tr(context, 'Create account'),
                              isLoading: false,
                              onPressed: _isLoading ? null : _openCreateAccount,
                              variant: AnimatedLoadingButtonVariant.outlined,
                            ),
                            const SizedBox(height: 28),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
