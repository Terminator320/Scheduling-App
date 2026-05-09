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
    final passwordErr = AuthValidators.password(
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _backToSignIn();
      },
      child: GestureDetector(
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
                child: _created
                    ? _buildSuccess(key: const ValueKey('success'))
                    : _buildForm(key: const ValueKey('form')),
              ),
            ),
          ),
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
        children:
            <Widget>[
                  const _CreateAccountLogo(),
                  const SizedBox(height: AppSpacing.sp24),
                  const _CreateAccountHeaderText(),
                  const SizedBox(height: AppSpacing.sp32),
                  _CreateAccountEmailField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    enabled: !_isLoading,
                    errorText: _emailError,
                    onSubmitted: _passwordFocus.requestFocus,
                    onChanged: _onFieldChanged,
                  ),
                  const SizedBox(height: AppSpacing.sp16),
                  _CreateAccountPasswordField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    enabled: !_isLoading,
                    errorText: _passwordError,
                    isObscured: _isObscured,
                    onSubmitted: _confirmPasswordFocus.requestFocus,
                    onChanged: _onFieldChanged,
                    onToggleObscured: () =>
                        setState(() => _isObscured = !_isObscured),
                  ),
                  const SizedBox(height: AppSpacing.sp16),
                  _CreateAccountConfirmField(
                    controller: _confirmPasswordController,
                    focusNode: _confirmPasswordFocus,
                    enabled: !_isLoading,
                    errorText: _confirmPasswordError,
                    isObscured: _isConfirmObscured,
                    onSubmitted: _createAccount,
                    onChanged: _onFieldChanged,
                    onToggleObscured: () => setState(
                      () => _isConfirmObscured = !_isConfirmObscured,
                    ),
                  ),
                  _CreateAccountErrorBanner(message: _bannerError),
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
                ]
                .animate(interval: 65.ms)
                .fadeIn(duration: 425.ms, curve: Curves.easeOutCubic)
                .slideY(
                  begin: 0.28,
                  duration: 425.ms,
                  curve: Curves.easeOutCubic,
                ),
      ),
    );
  }

  Widget _buildSuccess({required Key key}) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;

    return KeyedSubtree(
      key: key,
      child: Column(
        key: ValueKey('success_$_restartTick'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children:
            <Widget>[
                  Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: scheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(AppRadius.r12),
                        ),
                        child: Icon(
                          Icons.check_circle_outline_rounded,
                          size: 22,
                          color: scheme.tertiary,
                        ),
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
                  Text(
                    context.l10n.auth_accountCreated,
                    style: textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.auth_youCanNowSignInWithThisEmailAndPassword,
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sp32),
                  AnimatedLoadingButton(
                    label: context.l10n.auth_backToSignIn,
                    onPressed: _backToSignIn,
                  ),
                ]
                .animate(interval: 65.ms)
                .fadeIn(duration: 425.ms, curve: Curves.easeOutCubic)
                .slideY(
                  begin: 0.28,
                  duration: 425.ms,
                  curve: Curves.easeOutCubic,
                ),
      ),
    );
  }
}

class _CreateAccountLogo extends StatelessWidget {
  const _CreateAccountLogo();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
    );
  }
}

class _CreateAccountHeaderText extends StatelessWidget {
  const _CreateAccountHeaderText();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.auth_createAccount, style: textTheme.headlineLarge),
        const SizedBox(height: 4),
        Text(
          context.l10n.auth_useTheEmailYourAdminAddedToTheEmployeeList,
          style: textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _CreateAccountEmailField extends StatelessWidget {
  const _CreateAccountEmailField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.errorText,
    required this.onSubmitted,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String? errorText;
  final VoidCallback onSubmitted;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedFormFieldWrapper(
      hasError: errorText != null,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.email],
        enabled: enabled,
        onSubmitted: (_) => onSubmitted(),
        onChanged: (_) => onChanged(),
        decoration: formInputDecoration(context, context.l10n.common_email)
            .copyWith(
              errorText: errorText,
              prefixIcon: const Icon(Icons.email_outlined, size: 20),
            ),
      ),
    );
  }
}

class _CreateAccountPasswordField extends StatelessWidget {
  const _CreateAccountPasswordField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.errorText,
    required this.isObscured,
    required this.onSubmitted,
    required this.onChanged,
    required this.onToggleObscured,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String? errorText;
  final bool isObscured;
  final VoidCallback onSubmitted;
  final VoidCallback onChanged;
  final VoidCallback onToggleObscured;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedFormFieldWrapper(
      hasError: errorText != null,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: isObscured,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.newPassword],
        enabled: enabled,
        onSubmitted: (_) => onSubmitted(),
        onChanged: (_) => onChanged(),
        decoration: formInputDecoration(context, context.l10n.common_password)
            .copyWith(
              errorText: errorText,
              prefixIcon: const Icon(Icons.lock_outlined, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  isObscured
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                tooltip: isObscured
                    ? context.l10n.auth_showPassword
                    : context.l10n.auth_hidePassword,
                onPressed: onToggleObscured,
              ),
            ),
      ),
    );
  }
}

class _CreateAccountConfirmField extends StatelessWidget {
  const _CreateAccountConfirmField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.errorText,
    required this.isObscured,
    required this.onSubmitted,
    required this.onChanged,
    required this.onToggleObscured,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String? errorText;
  final bool isObscured;
  final VoidCallback onSubmitted;
  final VoidCallback onChanged;
  final VoidCallback onToggleObscured;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedFormFieldWrapper(
      hasError: errorText != null,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: isObscured,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.newPassword],
        enabled: enabled,
        onSubmitted: (_) => onSubmitted(),
        onChanged: (_) => onChanged(),
        decoration:
            formInputDecoration(
              context,
              context.l10n.auth_confirmPassword,
            ).copyWith(
              errorText: errorText,
              prefixIcon: const Icon(Icons.lock_reset_outlined, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  isObscured
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                tooltip: isObscured
                    ? context.l10n.auth_showPassword
                    : context.l10n.auth_hidePassword,
                onPressed: onToggleObscured,
              ),
            ),
      ),
    );
  }
}

class _CreateAccountErrorBanner extends StatelessWidget {
  const _CreateAccountErrorBanner({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return AnimatedSwitcher(
      duration: AppAnimationDurations.banner,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          alignment: AlignmentDirectional.topStart,
          child: child,
        ),
      ),
      child: message != null
          ? Padding(
              key: ValueKey('err_$message'),
              padding: const EdgeInsets.only(top: AppSpacing.sp12),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sp12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppRadius.r8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: scheme.error, size: 16),
                    const SizedBox(width: AppSpacing.sp8),
                    Expanded(
                      child: Text(
                        message!,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('banner_none')),
    );
  }
}
