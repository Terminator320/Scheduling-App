import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/features/auth/data/auth_error_mapper.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/auth/widgets/auth_banner.dart';
import 'package:scheduling/features/auth/widgets/auth_form_widgets.dart';
import 'package:scheduling/l10n/l10n.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail, this.authService});

  final String? initialEmail;

  final AuthService? authService;

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends ConsumerState<ForgotPasswordScreen> {
  late final AuthService _authService =
      widget.authService ?? ref.read(authServiceProvider);
  late final TextEditingController _emailController;

  bool _isLoading = false;
  bool _emailSent = false;
  String? _emailError;
  String _errorMessage = '';
  int _restartTick = 0;

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
    } catch (error, st) {
      final failure = AuthErrorMapper.map(error);
      AppLogger().authFailure(
        'auth.forgot_password reset failed',
        failure,
        error,
        st,
      );
      if (!mounted) return;
      systemError = failure.toForgotPasswordMessage(context);
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (systemError != null) {
        _errorMessage = systemError;
      } else {
        _emailSent = true;
        _restartTick++;
      }
    });
  }

  void _resendEmail() {
    setState(() {
      _emailSent = false;
      _errorMessage = '';
      _restartTick++;
    });
  }

  void _backToSignIn() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: AuthFormSwitcher(
        child: _emailSent
            ? _buildSuccess(key: ValueKey('success_$_restartTick'))
            : _buildForm(key: ValueKey('form_$_restartTick')),
      ),
    );
  }

  Widget _buildForm({required Key key}) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthBrandHeader(
          title: context.l10n.auth_forgotYourPassword,
          subtitle: context
              .l10n
              .auth_enterYourAccountEmailAndWeLlSendYouALinkToResetYourPassword,
        ),
        const SizedBox(height: AppSpacing.sp32),
        AuthEmailField(
          controller: _emailController,
          enabled: !_isLoading,
          errorText: _emailError,
          hint: context.l10n.auth_youExampleCom,
          textInputAction: TextInputAction.done,
          onSubmitted: _sendResetEmail,
          onChanged: () {
            if (_emailError != null || _errorMessage.isNotEmpty) {
              setState(() {
                _emailError = null;
                _errorMessage = '';
              });
            }
          },
        ),
        AuthBanner(
          message: _errorMessage.isEmpty ? null : _errorMessage,
        ),
        const SizedBox(height: AppSpacing.sp24),
        AnimatedLoadingButton(
          label: context.l10n.auth_sendResetEmail,
          isLoading: _isLoading,
          onPressed: _sendResetEmail,
        ),
        const SizedBox(height: AppSpacing.sp16),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : _backToSignIn,
            child: Text(
              context.l10n.auth_backToSignIn,
              style: textTheme.bodySmall?.copyWith(color: scheme.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess({required Key key}) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: AuthIconBadge(
            icon: Icons.mark_email_read_rounded,
            background: theme.statusColors.successContainer,
            foreground: theme.statusColors.success,
          ),
        ),
        const SizedBox(height: AppSpacing.sp24),
        AuthHeaderText(
          title: context.l10n.auth_checkYourInbox,
          subtitle: context
              .l10n
              .auth_ifAnAccountExistsForThisEmailAPasswordResetLinkHasBeenSent,
        ),
        const SizedBox(height: AppSpacing.sp16),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sp12),
          decoration: BoxDecoration(
            color: theme.statusColors.successContainer,
            borderRadius: BorderRadius.circular(AppRadius.r8),
            border: Border.all(
              color: theme.statusColors.success.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                color: theme.statusColors.success,
                size: 16,
              ),
              const SizedBox(width: AppSpacing.sp8),
              Expanded(
                child: Text(
                  context
                      .l10n
                      .auth_theEmailMayTakeAFewMinutesToArriveRememberToCheckYourSpamFolder,
                  style: textTheme.bodySmall?.copyWith(
                    color: theme.statusColors.onSuccessContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sp24),
        AnimatedLoadingButton(
          label: context.l10n.auth_backToSignIn,
          onPressed: _backToSignIn,
        ),
        const SizedBox(height: AppSpacing.sp16),
        Center(
          child: TextButton(
            onPressed: _resendEmail,
            child: Text(
              context.l10n.auth_didnTReceiveTheEmailTryAgain,
              style: textTheme.bodySmall?.copyWith(color: scheme.primary),
            ),
          ),
        ),
      ],
    );
  }
}
