import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/auth/data/auth_error_mapper.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/auth/widgets/auth_banner.dart';
import 'package:scheduling/features/auth/widgets/auth_form_widgets.dart';
import 'package:scheduling/features/auth/widgets/password_requirements_checklist.dart';
import 'package:scheduling/l10n/l10n.dart';

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
  final TextEditingController _codeController = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();
  final FocusNode _codeFocus = FocusNode();

  bool _isObscured = true;
  bool _isConfirmObscured = true;
  bool _isLoading = false;
  bool _submitted = false;

  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _codeError;
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
    _codeController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _codeFocus.dispose();
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

    final codeErr = _codeController.text.trim().isEmpty
        ? context.l10n.validation_pleaseEnterYourSignupCode
        : null;

    setState(() {
      _emailError = emailErr;
      _passwordError = passwordErr;
      _confirmPasswordError = confirmErr;
      _codeError = codeErr;
    });

    return emailErr == null &&
        passwordErr == null &&
        confirmErr == null &&
        codeErr == null;
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
      await _authService.signUpWithCode(
        email: _emailController.text,
        password: _passwordController.text,
        code: _codeController.text,
      );

      // OS password manager save prompt.
      TextInput.finishAutofillContext();

      if (!mounted) return;
      // The account is now active and the user is signed in. Pop back to the
      // sign-in flow with created:true; the caller routes the signed-in user in.
      Navigator.of(context).pop(
        CreateAccountResult(
          created: true,
          email: _emailController.text.trim().toLowerCase(),
        ),
      );
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
        created: false,
        email: _emailController.text.trim().toLowerCase(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _backToSignIn();
      },
      child: AuthScaffold(child: _buildForm()),
    );
  }

  Widget _buildForm() {
    return Column(
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
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          controller: _confirmPasswordController,
          focusNode: _confirmPasswordFocus,
          enabled: !_isLoading,
          errorText: _confirmPasswordError,
          isObscured: _isConfirmObscured,
          onSubmitted: _codeFocus.requestFocus,
          onChanged: _onFieldChanged,
          onToggleObscured: () =>
              setState(() => _isConfirmObscured = !_isConfirmObscured),
        ),
        const SizedBox(height: AppSpacing.sp16),
        AuthCodeField(
          label: context.l10n.auth_signupCode,
          controller: _codeController,
          focusNode: _codeFocus,
          enabled: !_isLoading,
          errorText: _codeError,
          maxLength: TextLimits.signupCode,
          onSubmitted: _createAccount,
          onChanged: _onFieldChanged,
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
    );
  }
}
