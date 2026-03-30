import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../screens/employee/employee_calendar.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_text.dart';
import '../../utils/colors.dart';

class LoginLightScreen extends StatefulWidget {
  const LoginLightScreen({super.key});

  @override
  State<LoginLightScreen> createState() => _LoginLightScreenState();
}

class _LoginLightScreenState extends State<LoginLightScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
      final credential = await AuthService.signIn(
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

      final userDoc = await UserService.findUserByUid(user.uid);

      if (!mounted) return;

      if (userDoc == null || !userDoc.exists) {
        setState(() {
          _errorMessage = 'No user profile found for this account.';
        });
        return;
      }

      final data = userDoc.data();
      final role = (data['role'] ?? '').toString();
      final isAdmin = data['isAdmin'] == true;
      final employeeName = (data['name'] ?? 'Employee').toString();
      final employeeId = userDoc.id;

      final canAccessAdminMode = role == 'admin' || isAdmin;

      if (canAccessAdminMode) {
        Navigator.pushReplacementNamed(context, '/admin/calendar/light');
      } else if (role == 'employee') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EmployeeCalendarPage(
              employeeId: employeeId,
              employeeName: employeeName,
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

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim().toLowerCase();

    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Enter your email first';
      });
      return;
    }

    try {
      await AuthService.sendResetPassword(email);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Password reset email sent')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message ?? 'Could not send reset email';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthCardScaffold(
      isDark: false,
      title: tr(context, 'Login'),
      subtitle: tr(context, 'Enter email and password'),
      emailController: _emailController,
      passwordController: _passwordController,
      isLoading: _isLoading,
      errorMessage: _errorMessage,
      primaryButtonText: tr(context, 'Sign In'),
      onPrimaryPressed: _signIn,
      onForgotPassword: _resetPassword,
      onSecondaryTap: () {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreateAccountLightScreen(),
          ),
        );
      },
      secondaryText: tr(context, 'Create account'),
      secondaryTextColor: Colors.black,
    );
  }
}

class CreateAccountLightScreen extends StatefulWidget {
  const CreateAccountLightScreen({super.key});

  @override
  State<CreateAccountLightScreen> createState() =>
      _CreateAccountLightScreenState();
}

class _CreateAccountLightScreenState extends State<CreateAccountLightScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

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
      final credential = await AuthService.createEmployeeAccount(
        email: email,
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Could not create account';
        });
        return;
      }

      final userDoc = await UserService.findUserByUid(user.uid);

      if (!mounted) return;

      if (userDoc == null || !userDoc.exists) {
        setState(() {
          _errorMessage = 'No user profile found for this account.';
        });
        return;
      }

      final data = userDoc.data();
      final role = (data['role'] ?? '').toString();
      final isAdmin = data['isAdmin'] == true;
      final employeeName = (data['name'] ?? 'Employee').toString();
      final employeeId = userDoc.id;

      final canAccessAdminMode = role == 'admin' || isAdmin;

      if (canAccessAdminMode) {
        Navigator.pushReplacementNamed(context, '/admin/calendar/light');
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EmployeeCalendarPage(
              employeeId: employeeId,
              employeeName: employeeName,
            ),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message ?? 'Could not create account';
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

  @override
  Widget build(BuildContext context) {
    return _AuthCardScaffold(
      isDark: false,
      title: tr(context, 'Create Account'),
      subtitle: tr(context, 'Enter email and password'),
      emailController: _emailController,
      passwordController: _passwordController,
      isLoading: _isLoading,
      errorMessage: _errorMessage,
      primaryButtonText: tr(context, 'Create Account'),
      onPrimaryPressed: _createAccount,
      onForgotPassword: null,
      onSecondaryTap: () {
        if (!mounted) return;
        Navigator.pop(context);
      },
      secondaryText: tr(context, 'Sign in'),
      secondaryTextColor: Colors.black,
    );
  }
}

class _AuthCardScaffold extends StatelessWidget {
  const _AuthCardScaffold({
    required this.isDark,
    required this.title,
    required this.subtitle,
    required this.emailController,
    required this.passwordController,
    required this.isLoading,
    required this.errorMessage,
    required this.primaryButtonText,
    required this.onPrimaryPressed,
    required this.onForgotPassword,
    required this.onSecondaryTap,
    required this.secondaryText,
    required this.secondaryTextColor,
  });

  final bool isDark;
  final String title;
  final String subtitle;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isLoading;
  final String errorMessage;
  final String primaryButtonText;
  final VoidCallback onPrimaryPressed;
  final VoidCallback? onForgotPassword;
  final VoidCallback onSecondaryTap;
  final String secondaryText;
  final Color secondaryTextColor;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isDark ? Colors.black : Color(0xFFF2F2F2);
    final cardColor = isDark ? Colors.transparent : Colors.white;
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;
    final titleColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark ? Colors.white70 : Colors.black;
    final inputTextColor = isDark ? Colors.white : Colors.black;
    final inputLabelColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Container(
            width: 320,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(8),
              color: cardColor,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 22, color: titleColor),
                ),
                SizedBox(height: 10),
                Text(
                  subtitle,
                  style: TextStyle(color: subtitleColor),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: inputTextColor),
                  decoration: InputDecoration(
                    labelText: tr(context, 'Email'),
                    labelStyle: TextStyle(color: inputLabelColor),
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: TextStyle(color: inputTextColor),
                  decoration: InputDecoration(
                    labelText: tr(context, 'Password'),
                    labelStyle: TextStyle(color: inputLabelColor),
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPurple,
                    ),
                    onPressed: isLoading ? null : onPrimaryPressed,
                    child: isLoading
                        ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                        : Text(
                      primaryButtonText,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                if (errorMessage.isNotEmpty) ...[
                  SizedBox(height: 10),
                  Text(
                    errorMessage,
                    style: TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (onForgotPassword != null) ...[
                  SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () {
                        onForgotPassword?.call();
                      },
                      child: Text(
                        tr(context, 'Forgot password?'),
                        style: TextStyle(
                          color: secondaryTextColor,
                          decoration: TextDecoration.underline,
                          decorationColor: secondaryTextColor,
                          decorationThickness: 2,
                        ),
                      ),
                    ),
                  ),
                ],
                SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () {
                      onSecondaryTap();
                    },
                    child: Text(
                      secondaryText,
                      style: TextStyle(
                        color: secondaryTextColor,
                        decoration: TextDecoration.underline,
                        decorationColor: secondaryTextColor,
                        decorationThickness: 2,
                      ),
                    ),
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