import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/features/auth/data/auth_error_mapper.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/auth/widgets/auth_banner.dart';
import 'package:scheduling/features/auth/widgets/auth_form_widgets.dart';
import 'package:scheduling/features/auth/widgets/password_requirements_checklist.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/busy_button_icon.dart';

class CreateAccountResult {
  const CreateAccountResult({required this.created, this.email});

  final bool created;
  final String? email;
}

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key, this.initialEmail, this.authService});

  final String? initialEmail;

  final AuthService? authService;

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  late final AuthService _authService = widget.authService ?? AuthService();
  late final TextEditingController _emailController;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();

  int _restartTick = 0;

  bool _isObscured = true;
  bool _isConfirmObscured = true;
  bool _isLoading = false;
  bool _submitted = false;
  bool _created = false;
  bool _isResending = false;
  bool _resendFailed = false;
  String? _resendMessage;

  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _bannerError;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  bool _validate() {
    final emailErr = AuthValidators.email(context, _emailController.text);
    final passwordErr = AuthValidators.newPassword(
      context,
      _passwordController.text,
    );

    String? confirmErr;
    if (_confirmPasswordController.text.trim().isEmpty) {
      confirmErr = context.l10n.validation_pleaseConfirmYourPassword;
    } else if (_confirmPasswordController.text.trim() !=
        _passwordController.text.trim()) {
      confirmErr = context.l10n.validation_passwordsDoNotMatch;
    }

    setState(() {
      _emailError = emailErr;
      _passwordError = passwordErr;
      _confirmPasswordError = confirmErr;
    });

    return emailErr == null && passwordErr == null && confirmErr == null;
  }

  void _onFieldChanged() {
    if (_submitted) _validate();
    if (_bannerError != null) {
      setState(() => _bannerError = null);
    }
  }

  void _onPasswordChanged() {
    // Rebuild so the requirements checklist tracks every keystroke.
    setState(() {});
    _onFieldChanged();
  }

  Future<void> _createAccount() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _submitted = true;
      _bannerError = null;
    });

    if (!_validate()) return;

    setState(() => _isLoading = true);

    try {
      await _authService.createEmployeeAccount(
        email: _emailController.text,
        password: _passwordController.text,
      );

      // Commit the autofill context so the OS password manager offers to
      // save the freshly created credentials.
      TextInput.finishAutofillContext();

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _created = true;
        _restartTick++;
      });
    } catch (error) {
      if (!mounted) return;
      final failure = AuthErrorMapper.map(error);
      setState(() {
        _bannerError = failure.toLocalizedMessageInContext(
          context,
          AuthErrorContext.register,
        );
        _isLoading = false;
      });
    }
  }

  void _backToSignIn() {
    Navigator.of(context).pop(
      CreateAccountResult(
        created: _created,
        email: _emailController.text.trim().toLowerCase(),
      ),
    );
  }

  Future<void> _resendVerification() async {
    final user = _authService.currentUser;
    if (user == null) {
      // No current session (e.g. signed out by the login auto-resend path) —
      // surface it instead of a silent no-op so the user isn't left waiting.
      setState(() {
        _resendFailed = true;
        _resendMessage = context.l10n.error_somethingWentWrongPleaseTryAgain;
      });
      return;
    }
    setState(() {
      _isResending = true;
      _resendMessage = null;
    });
    final sent = await _authService.resendVerificationEmail(user);
    if (!mounted) return;
    setState(() {
      _isResending = false;
      _resendFailed = !sent;
      _resendMessage = sent
          ? context.l10n.auth_verificationEmailSentCheckInboxAndSpam
          : context.l10n.error_somethingWentWrongPleaseTryAgain;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _backToSignIn();
      },
      child: AuthScaffold(
        child: AuthFormSwitcher(
          child: _created
              ? _buildSuccess(key: const ValueKey('success'))
              : _buildForm(key: const ValueKey('form')),
        ),
      ),
    );
  }

  Widget _buildForm({required Key key}) {
    return KeyedSubtree(
      key: key,
      child: Column(
        key: ValueKey('form_$_restartTick'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const AuthLogo(),
          const SizedBox(height: AppSpacing.sp24),
          AuthHeaderText(
            title: context.l10n.auth_createAccount,
            subtitle:
                context.l10n.auth_useTheEmailYourAdminAddedToTheEmployeeList,
          ),
          const SizedBox(height: AppSpacing.sp32),
          AuthEmailField(
            controller: _emailController,
            focusNode: _emailFocus,
            enabled: !_isLoading,
            errorText: _emailError,
            onSubmitted: _passwordFocus.requestFocus,
            onChanged: _onFieldChanged,
          ),
          const SizedBox(height: AppSpacing.sp16),
          AuthPasswordField(
            label: context.l10n.common_password,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            controller: _passwordController,
            focusNode: _passwordFocus,
            enabled: !_isLoading,
            errorText: _passwordError,
            isObscured: _isObscured,
            onSubmitted: _confirmPasswordFocus.requestFocus,
            onChanged: _onPasswordChanged,
            onToggleObscured: () => setState(() => _isObscured = !_isObscured),
          ),
          const SizedBox(height: AppSpacing.sp12),
          PasswordRequirementsChecklist(password: _passwordController.text),
          const SizedBox(height: AppSpacing.sp16),
          AuthPasswordField(
            label: context.l10n.auth_confirmPassword,
            prefixIcon: Icons.lock_reset_outlined,
            autofillHints: const [AutofillHints.newPassword],
            controller: _confirmPasswordController,
            focusNode: _confirmPasswordFocus,
            enabled: !_isLoading,
            errorText: _confirmPasswordError,
            isObscured: _isConfirmObscured,
            onSubmitted: _createAccount,
            onChanged: _onFieldChanged,
            onToggleObscured: () =>
                setState(() => _isConfirmObscured = !_isConfirmObscured),
          ),
          AuthBanner(message: _bannerError),
          const SizedBox(height: AppSpacing.sp24),
          AnimatedLoadingButton(
            label: context.l10n.auth_createAccount,
            isLoading: _isLoading,
            onPressed: _createAccount,
          ),
          const SizedBox(height: AppSpacing.sp16),
          Center(
            child: TextButton(
              onPressed: _isLoading ? null : _backToSignIn,
              child: Text(
                context.l10n.auth_backToSignIn,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ].authStaggerIn(),
      ),
    );
  }

  Widget _buildSuccess({required Key key}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return KeyedSubtree(
      key: key,
      child: Column(
        key: ValueKey('success_$_restartTick'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AuthIconBadge(
                icon: Icons.check_circle_outline_rounded,
                background: theme.statusColors.successContainer,
                foreground: theme.statusColors.success,
              )
              .animate()
              .scale(
                begin: const Offset(0.82, 0.82),
                end: const Offset(1, 1),
                duration: 425.ms,
                curve: Curves.easeOutCubic,
              )
              .fadeIn(duration: 425.ms, curve: Curves.easeOutCubic),
          const SizedBox(height: AppSpacing.sp24),
          AuthHeaderText(
            title: context.l10n.auth_accountCreated,
            subtitle: context.l10n.auth_youCanNowSignInWithThisEmailAndPassword,
          ),
          AuthBanner(
            message: _resendMessage,
            kind: _resendFailed ? AuthBannerKind.error : AuthBannerKind.success,
          ),
          const SizedBox(height: AppSpacing.sp24),
          AnimatedLoadingButton(
            label: context.l10n.auth_backToSignIn,
            onPressed: _backToSignIn,
          ),
          const SizedBox(height: AppSpacing.sp8),
          Center(
            child: TextButton.icon(
              onPressed: _isResending ? null : _resendVerification,
              icon: BusyButtonIcon(
                isBusy: _isResending,
                icon: Icons.refresh,
                color: scheme.primary,
              ),
              label: Text(context.l10n.auth_resendVerificationEmail),
            ),
          ),
        ].authStaggerIn(),
      ),
    );
  }
}
