import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_text.dart';
import '../utils/calendar_utils/appointment_colors.dart';
import '../models/employee_record.dart';
import 'main_calendar.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  //password visibility
  bool _isObscured = true;

  bool _isLoading = false;
  String _errorMessage = '';

  // Create account
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

  // Sign
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

      //check if user account is active
      final user = credential.user;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Login failed';
        });
        return;
      }

      // check if user profile exists
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

      final employeeName = employee.name;
      final employeeId = employee.id;

      final canAccessAdminMode = employee.isAdmin;

      if (canAccessAdminMode) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MainCalendar(
              // employeeId: employeeId,
              // employeeName: employeeName,
            ),
          ),
        );
      } else if (employee.role == 'employee') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MainCalendar(
              // employeeId: employeeId,
              // employeeName: employeeName,
            ),
          ),
        );
      } else {
        setState(() {
          _errorMessage = 'Unknown user role';
        });
      }
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

  //reset password
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

    String title = tr(context, 'Login');
    String confirmButton = tr(context, 'Sign In');

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 26),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colour.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: colour.onSurface.withOpacity(0.08),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: textTheme.labelLarge?.copyWith(
                      color: colour.onSurface,
                      fontSize: 26,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10),
                  Text(
                    tr(context, 'Enter email and password'),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colour.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20),

                  // email textfeild
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colour.onSurface,
                    ),
                    decoration: InputDecoration(
                      labelText: tr(context, 'Email'),
                      border: OutlineInputBorder(),
                    ),
                  ),

                  SizedBox(height: 12),

                  // password textfeild
                  TextField(
                    controller: _passwordController,
                    obscureText: _isObscured,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colour.onSurface.withOpacity(0.7),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      labelStyle: textTheme.bodySmall,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isObscured ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _isObscured = !_isObscured;
                          });
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _signIn,
                      child: _isLoading
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: colour.onPrimary,
                              ),
                            )
                          : Text(confirmButton),
                    ),
                  ),

                  if (_errorMessage.isNotEmpty) ...[
                    SizedBox(height: 10),
                    Text(
                      _errorMessage,
                      style: TextStyle(color: colour.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  SizedBox(height: 10 ),
                  InkWell(
                    onTap: _isLoading ? null : _createAccount,
                    child: Text(
                      tr(context, 'Create account'),
                      style: textTheme.labelSmall,
                      textAlign: TextAlign.left,
                    ),
                  ),
                  SizedBox(height: 10),
                  InkWell(
                    onTap: _resetPassword,
                    child: Text(
                      tr(context, 'Forgot Password'),
                      style: textTheme.labelSmall,
                      textAlign: TextAlign.left,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
