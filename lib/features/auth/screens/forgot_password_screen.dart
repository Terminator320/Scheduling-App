import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:scheduling/core/utils/app_text.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/auth/widgets/auth_banner.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';

class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  late final TextEditingController _emailController;

  bool _isLoading = false;
  bool _emailSent = false;
  String? _emailError;
  String _errorMessage = '';

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim().toLowerCase();

    if (email.isEmpty) {
      setState(() {
        _emailError = tr(context, 'Please enter your email');
        _errorMessage = '';
      });
      return;
    }

    if (!_emailPattern.hasMatch(email)) {
      setState(() {
        _emailError = tr(context, 'Please enter a valid email address');
        _errorMessage = '';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _emailError = null;
      _errorMessage = '';
    });

    // Privacy: we deliberately do NOT differentiate between "email exists"
    // and "email does not exist". Errors that would reveal account state
    // (user-not-found, user-disabled, server-side invalid-email) are
    // swallowed — the UI always lands on the same neutral message.
    // Only errors about the request itself (network, rate limit) are
    // surfaced, because they don't leak per-email state.
    String? systemError;
    try {
      await AuthService().sendResetPassword(email);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'too-many-requests':
          systemError = tr(
            context,
            'Too many attempts, please try again later',
          );
          break;
        case 'network-request-failed':
          systemError = tr(
            context,
            'Network error. Check your connection and try again',
          );
          break;
        default:
          break;
      }
    } catch (_) {
      systemError = tr(context, 'Something went wrong, please try again');
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (systemError != null) {
        _errorMessage = systemError;
      } else {
        _emailSent = true;
      }
    });
  }

  void _resendEmail() {
    setState(() {
      _emailSent = false;
      _errorMessage = '';
    });
  }

  void _backToSignIn() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: tr(context, 'Back'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(tr(context, 'Reset Password')),
          centerTitle: true,
          elevation: 0,
          backgroundColor: colour.surface,
          foregroundColor: colour.onSurface,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 400,
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom -
                      kToolbarHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: _emailSent ? _buildSuccess() : _buildForm(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final colour = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colour.primary.withAlpha(28),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lock_reset_rounded,
              size: 36,
              color: colour.primary,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          tr(context, 'Forgot your password?'),
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          tr(
            context,
            'Enter your account email and we\'ll send you a link to reset your password.',
          ),
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: colour.onSurface.withAlpha(160),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            tr(context, 'Email'),
            style: textTheme.labelLarge?.copyWith(
              color: colour.onSurface.withAlpha(200),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          textInputAction: TextInputAction.done,
          enabled: !_isLoading,
          onSubmitted: (_) => _sendResetEmail(),
          onChanged: (_) {
            if (_emailError != null || _errorMessage.isNotEmpty) {
              setState(() {
                _emailError = null;
                _errorMessage = '';
              });
            }
          },
          decoration: formInputDecoration(context, 'you@example.com').copyWith(
            errorText: _emailError,
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
          ),
        ),
        if (_errorMessage.isNotEmpty) ...[
          const SizedBox(height: 14),
          AuthBanner(
            kind: AuthBannerKind.error,
            message: _errorMessage,
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _isLoading ? null : _sendResetEmail,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
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
                    tr(context, 'Send Reset Email'),
                    style: textTheme.titleSmall?.copyWith(
                      color: colour.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _isLoading ? null : _backToSignIn,
          child: Text(
            tr(context, 'Back to Sign In'),
            style: textTheme.bodyMedium?.copyWith(
              color: colour.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    final colour = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: colour.secondary.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mark_email_read_rounded,
              size: 44,
              color: colour.secondary,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          tr(context, 'Check your inbox'),
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        AuthBanner(
          kind: AuthBannerKind.success,
          message: tr(
            context,
            'If an account exists for this email, a password reset link has been sent.',
          ),
        ),
        const SizedBox(height: 16),
        AuthBanner(
          kind: AuthBannerKind.info,
          message: tr(
            context,
            'The email may take a few minutes to arrive. Remember to check your spam folder.',
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _backToSignIn,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              tr(context, 'Back to Sign In'),
              style: textTheme.titleSmall?.copyWith(
                color: colour.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _resendEmail,
          child: Text(
            tr(context, 'Use a different email'),
            style: textTheme.bodySmall?.copyWith(
              color: colour.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
