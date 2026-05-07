import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:scheduling/core/animations/animated_form_field_wrapper.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/features/auth/data/auth_error_mapper.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail, this.authService});

  final String? initialEmail;

  final AuthService? authService;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPasswordScreen> {
  late final AuthService _authService = widget.authService ?? AuthService();
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
    } catch (error) {
      if (!mounted) return;
      final failure = AuthErrorMapper.map(error);
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
    final scheme = Theme.of(context).colorScheme;
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
                  ? _buildSuccess(key: ValueKey('success_$_restartTick'))
                  : _buildForm(key: ValueKey('form_$_restartTick')),
            ),
          ),
        ),
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
      children:
          [
                Container(
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
                const SizedBox(height: AppSpacing.sp24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.auth_forgotYourPassword,
                      style: textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context
                          .l10n
                          .auth_enterYourAccountEmailAndWeLlSendYouALinkToResetYourPassword,
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sp32),
                AnimatedFormFieldWrapper(
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
                    decoration:
                        formInputDecoration(
                          context,
                          context.l10n.auth_youExampleCom,
                        ).copyWith(
                          errorText: _emailError,
                          prefixIcon: const Icon(
                            Icons.email_outlined,
                            size: 20,
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
                          padding: const EdgeInsets.only(top: AppSpacing.sp12),
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.sp12),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(AppRadius.r8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: scheme.error,
                                  size: 16,
                                ),
                                const SizedBox(width: AppSpacing.sp8),
                                Expanded(
                                  child: Text(
                                    _errorMessage,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: scheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('error_none')),
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
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
              ]
              .animate(interval: 65.ms)
              .fadeIn(duration: 425.ms, curve: Curves.easeOutCubic)
              .slideY(
                begin: 0.28,
                duration: 425.ms,
                curve: Curves.easeOutCubic,
              ),
    );
  }

  Widget _buildSuccess({required Key key}) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                  ),
                  child: Icon(
                    Icons.mark_email_read_rounded,
                    size: 22,
                    color: scheme.tertiary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sp24),
                Text(
                  context.l10n.auth_checkYourInbox,
                  style: textTheme.headlineLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  context
                      .l10n
                      .auth_ifAnAccountExistsForThisEmailAPasswordResetLinkHasBeenSent,
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.sp16),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sp12),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.r8),
                    border: Border.all(
                      color: scheme.tertiary.withValues(alpha: 0.4),
                    ),
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
                          context
                              .l10n
                              .auth_theEmailMayTakeAFewMinutesToArriveRememberToCheckYourSpamFolder,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onTertiaryContainer,
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
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
              ]
              .animate(interval: 65.ms)
              .fadeIn(duration: 425.ms, curve: Curves.easeOutCubic)
              .slideY(
                begin: 0.28,
                duration: 425.ms,
                curve: Curves.easeOutCubic,
              ),
    );
  }
}
