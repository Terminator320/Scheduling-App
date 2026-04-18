import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_text.dart';
import '../models/employee_record.dart';
import '../utils/calendar_utils/form_widgets.dart';
import 'main_calendar.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isObscured = true;
  bool _isLoading = false;
  String _errorMessage = '';

  Future<void> _createAccount() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Email and password are required';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await AuthService().createEmployeeAccount(
        email: email,
        password: password,
      );

      setState(() {
        _errorMessage = 'Account created. You can now sign in.';
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'Account creation failed';
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Something went wrong';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Email and password are required';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final credential = await AuthService().signIn(
        email: email,
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Login failed';
        });
        return;
      }

      final userDoc = await UserService().findUserByUid(user.uid);

      if (!mounted) return;

      if (userDoc == null || !userDoc.exists) {
        setState(() {
          _errorMessage = 'No user profile found for this account.';
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
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message ?? 'Login failed';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim().toLowerCase();

    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Enter your email first';
      });
      return;
    }

    try {
      await AuthService().sendResetPassword(email);

      setState(() {
        _errorMessage = 'Password reset email sent';
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'Failed to send reset email';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).unfocus(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
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
                        keyboardType: TextInputType.emailAddress,
                        style: textTheme.bodyMedium,
                        decoration: formInputDecoration(context, 'Email')
                            .copyWith(
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
                        obscureText: _isObscured,
                        style: textTheme.bodyMedium,
                        decoration: formInputDecoration(context, 'Password')
                            .copyWith(
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
                          onPressed: _isLoading ? null : _resetPassword,
                          child: Text(
                            tr(context, 'Forgot Password'),
                            style: textTheme.bodySmall?.copyWith(
                              color: colour.primary,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Error message
                      if (_errorMessage.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            _errorMessage,
                            style: textTheme.bodySmall?.copyWith(
                              color: colour.error,
                            ),
                            textAlign: TextAlign.center,
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
                      SizedBox(
                        height: MediaQuery.of(context).viewInsets.bottom + 13,
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
