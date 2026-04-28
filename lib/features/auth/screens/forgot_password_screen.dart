import 'package:flutter/material.dart';

import 'package:scheduling/core/animations/animated_form_field_wrapper.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/animations/fade_slide_entrance.dart';
import 'package:scheduling/core/animations/staggered_entrance_controller.dart';
import 'package:scheduling/core/errors/auth_error_handler.dart';
import 'package:scheduling/core/utils/app_text.dart';
import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/auth/widgets/auth_banner.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';

class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class ForgotPasswordScreen extends ForgotPassword {
  const ForgotPasswordScreen({super.key, super.initialEmail});
}

class _ForgotPasswordState extends State<ForgotPassword>
    with SingleTickerProviderStateMixin {
  static const int _itemCount = 6;

  final AuthService _authService = AuthService();
  late final TextEditingController _emailController;
  late final StaggeredEntranceController _entrance;

  bool _isLoading = false;
  bool _emailSent = false;
  String? _emailError;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
    _entrance = StaggeredEntranceController(vsync: this, itemCount: _itemCount)
      ..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim().toLowerCase();
    final emailError = AuthValidators.email(context, email);

    if (emailError != null) {
      setState(() {
        _emailError = emailError;
        _errorMessage = '';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _emailError = null;
      _errorMessage = '';
    });

    String? systemError;
    try {
      await _authService.sendPasswordResetEmail(email);
    } catch (error) {
      // Keep account-existence errors private while still surfacing request
      systemError = AuthErrorHandler.getPasswordResetRequestMessage(
        context,
        error,
      );
    }

    if (!mounted) return;
    var shouldReplayEntrance = false;
    setState(() {
      _isLoading = false;
      if (systemError != null) {
        _errorMessage = systemError;
      } else {
        _emailSent = true;
        shouldReplayEntrance = true;
      }
    });
    // Replay the stagger so the success view animates in fresh.
    if (shouldReplayEntrance) {
      _entrance.controller.forward(from: 0);
    }
  }

  void _resendEmail() {
    setState(() {
      _emailSent = false;
      _errorMessage = '';
    });
    // Replay entrance so the form animates back in when switching views.
    _entrance.controller.forward(from: 0);
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
                  minHeight:
                      MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom -
                      kToolbarHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: AnimatedSwitcher(
                    duration: AppAnimationDurations.banner,
                    switchInCurve: AppAnimationCurves.entrance,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.04),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _emailSent
                        ? _buildSuccess(key: const ValueKey('success'))
                        : _buildForm(key: const ValueKey('form')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm({required Key key}) {
    final colour = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final animations = _entrance.animations;

    return Column(
      key: key,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1).animate(animations[0]),
          child: FadeTransition(
            opacity: animations[0],
            child: Center(
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
          ),
        ),
        const SizedBox(height: 24),
        FadeSlideEntrance(
          animation: animations[1],
          child: Column(
            children: [
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
            ],
          ),
        ),
        const SizedBox(height: 32),
        FadeSlideEntrance(
          animation: animations[2],
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              tr(context, 'Email'),
              style: textTheme.labelLarge?.copyWith(
                color: colour.onSurface.withAlpha(200),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        FadeSlideEntrance(
          animation: animations[3],
          child: AnimatedFormFieldWrapper(
            hasError: _emailError != null,
            child: TextField(
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
              decoration: formInputDecoration(context, 'you@example.com')
                  .copyWith(
                    errorText: _emailError,
                    prefixIcon: const Icon(Icons.email_outlined, size: 20),
                  ),
            ),
          ),
        ),
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
          child: _errorMessage.isNotEmpty
              ? Padding(
                  key: ValueKey('error_$_errorMessage'),
                  padding: const EdgeInsets.only(top: 14),
                  child: AuthBanner(
                    kind: AuthBannerKind.error,
                    message: _errorMessage,
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('error_none')),
        ),
        const SizedBox(height: 24),
        FadeSlideEntrance(
          animation: animations[4],
          child: AnimatedLoadingButton(
            label: tr(context, 'Send Reset Email'),
            isLoading: _isLoading,
            onPressed: _sendResetEmail,
          ),
        ),
        const SizedBox(height: 12),
        FadeSlideEntrance(
          animation: animations[5],
          child: TextButton(
            onPressed: _isLoading ? null : _backToSignIn,
            child: Text(
              tr(context, 'Back to Sign In'),
              style: textTheme.bodyMedium?.copyWith(
                color: colour.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess({required Key key}) {
    final colour = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final animations = _entrance.animations;

    return Column(
      key: key,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1).animate(animations[0]),
          child: FadeTransition(
            opacity: animations[0],
            child: Center(
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
          ),
        ),
        const SizedBox(height: 28),
        FadeSlideEntrance(
          animation: animations[1],
          child: Text(
            tr(context, 'Check your inbox'),
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 20),
        FadeSlideEntrance(
          animation: animations[2],
          child: AuthBanner(
            kind: AuthBannerKind.success,
            message: tr(
              context,
              'If an account exists for this email, a password reset link has been sent.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        FadeSlideEntrance(
          animation: animations[3],
          child: AuthBanner(
            kind: AuthBannerKind.info,
            message: tr(
              context,
              'The email may take a few minutes to arrive. Remember to check your spam folder.',
            ),
          ),
        ),
        const SizedBox(height: 32),
        FadeSlideEntrance(
          animation: animations[4],
          child: AnimatedLoadingButton(
            label: tr(context, 'Back to Sign In'),
            onPressed: _backToSignIn,
          ),
        ),
        const SizedBox(height: 8),
        FadeSlideEntrance(
          animation: animations[5],
          child: TextButton(
            onPressed: _resendEmail,
            child: Text(
              tr(context, 'Use a different email'),
              style: textTheme.bodySmall?.copyWith(
                color: colour.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
