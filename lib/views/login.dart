import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_text.dart';
import '../../utils/colors.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  String _errorMessage = '';


  @override
  Widget build(BuildContext context) {

    String title = tr(context, 'Login');
    String confirmButton = tr(context, 'Sign In');

    final backgroundColor = Color(0xFFF2F2F2);
    final cardColor = Colors.white;
    final borderColor = Colors.grey.shade300;
    final titleColor = Colors.black;
    final subtitleColor = Colors.black;
    final inputTextColor = Colors.black;
    final inputLabelColor = Colors.black54;
    final secondaryTextColor = Colors.black;

    Future<void> _createAccount() async {
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        setState(() {
          _errorMessage = 'Email and password are required';
        });
        return;
      }}


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
                  tr(context, 'Enter email and password'),
                  style: TextStyle(color: subtitleColor),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20),
                TextField(
                  controller: _emailController,
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
                  controller: _passwordController,
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
                    onPressed: _isLoading ? null : onPrimaryPressed,
                    child: _isLoading
                        ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                        : Text(
                      confirmButton,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                if (_errorMessage.isNotEmpty) ...[
                  SizedBox(height: 10),
                  Text(
                    _errorMessage,
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