import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_text.dart';
import '../models/employee_record.dart';
import '../utils/calendar_utils/form_widgets.dart';
import 'forgot_password.dart';
import 'main_calendar.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
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

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool _validate() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    String? emailErr;
    String? passwordErr;

    if (email.isEmpty) {
      emailErr = tr(context, 'Enter your email');
    } else if (!_emailPattern.hasMatch(email)) {
      emailErr = tr(context, 'Please enter a valid email address');
    }

    if (password.trim().isEmpty) {
      passwordErr = tr(context, 'Enter your password');
    }

    setState(() {
      _emailError = emailErr;
      _passwordError = passwordErr;
    });

    return emailErr == null && passwordErr == null;
  }

  void _onFieldChanged() {
    if (_submitted) {
      _validate();
    }
    if (_bannerError != null || _bannerSuccess != null) {
      setState(() {
        _bannerError = null;
        _bannerSuccess = null;
      });
    }
  }

  String _friendlyAuthError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return tr(context, 'Please enter a valid email address');
        case 'user-disabled':
          return tr(context, 'This account has been disabled');
        case 'user-not-found':
          return tr(context, 'No account found with this email');
        case 'wrong-password':
        case 'invalid-credential':
        case 'INVALID_LOGIN_CREDENTIALS':
          return tr(context, 'Invalid email or password');
        case 'too-many-requests':
          return tr(context, 'Too many attempts, please try again later');
        case 'network-request-failed':
          return tr(
            context,
            'Network error. Check your connection and try again',
          );
        case 'email-already-in-use':
          return tr(context, 'An account with this email already exists');
        case 'weak-password':
          return tr(
            context,
            'Password is too weak. Use at least 6 characters',
          );
        case 'operation-not-allowed':
          return tr(context, 'Sign-in is temporarily unavailable');
        case 'not-authorized':
          return tr(context, 'This email is not authorized to sign up');
      }
    }
    return tr(context, 'Something went wrong, please try again');
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
      final credential = await AuthService().signIn(
        email: _emailController.text.trim().toLowerCase(),
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

      final userDoc = await UserService().findUserByUid(user.uid);
      if (!mounted) return;

      if (userDoc == null || !userDoc.exists) {
        setState(() {
          _bannerError = tr(context, 'No user profile found for this account');
          _isLoading = false;
        });
        return;
      }

      final data = userDoc.data();
      final employee = EmployeeRecord.fromMap(userDoc.id, data);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              MainCalendar(isAdmin: employee.isAdmin, employeeId: employee.id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bannerError = _friendlyAuthError(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _createAccount() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _submitted = true;
      _bannerError = null;
      _bannerSuccess = null;
    });

    if (!_validate()) return;

    setState(() => _isLoading = true);

    try {
      await AuthService().createEmployeeAccount(
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      setState(() {
        _bannerSuccess = tr(context, 'Account created. You can now sign in.');
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bannerError = _friendlyAuthError(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _openForgotPassword() async {
    final prefill = _emailController.text.trim();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPassword(
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
      _bannerSuccess = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo
                      Image.asset('assets/logo1.png', height: 120),

                      const SizedBox(height: 15),

                      // Welcome text
                      Text(
                        tr(context, 'Sign In'),
                        style: textTheme.headlineLarge,
                      ),

                      const SizedBox(height: 8),

                      Text(
                        tr(context, 'Enter email and password'),
                        style: textTheme.bodyMedium?.copyWith(
                          color: colour.onSurface.withAlpha(150),
                        ),
                      ),

                      const SizedBox(height: 36),

                      // Email field
                      TextField(
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
                        decoration: formInputDecoration(context, 'Email').copyWith(
                          errorText: _emailError,
                          prefixIcon: const Icon(
                            Icons.email_outlined,
                            size: 20,
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Password field
                      TextField(
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        obscureText: _isObscured,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        enabled: !_isLoading,
                        onSubmitted: (_) => _signIn(),
                        onChanged: (_) => _onFieldChanged(),
                        decoration: formInputDecoration(context, 'Password').copyWith(
                          errorText: _passwordError,
                          prefixIcon: const Icon(
                            Icons.lock_outlined,
                            size: 20,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isObscured
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _isObscured = !_isObscured;
                              });
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Forgot password
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isLoading ? null : _openForgotPassword,
                          child: Text(
                            tr(context, 'Forgot Password'),
                            style: textTheme.bodySmall?.copyWith(
                              color: colour.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Banners
                      if (_bannerError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: AuthBanner(
                            kind: AuthBannerKind.error,
                            message: _bannerError!,
                          ),
                        ),
                      if (_bannerSuccess != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: AuthBanner(
                            kind: AuthBannerKind.success,
                            message: _bannerSuccess!,
                          ),
                        ),

                      // Sign in button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _signIn,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: colour.onPrimary,
                                  ),
                                )
                              : Text(
                                  tr(context, 'Sign In'),
                                  style: textTheme.titleSmall?.copyWith(
                                    color: colour.onPrimary,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Divider
                      Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'or',
                              style: textTheme.bodySmall?.copyWith(
                                color: colour.onSurface.withAlpha(100),
                              ),
                            ),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Create account button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : _createAccount,
                          child: Text(
                            tr(context, 'Create account'),
                            style: textTheme.titleSmall?.copyWith(
                              color: colour.primary,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
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

