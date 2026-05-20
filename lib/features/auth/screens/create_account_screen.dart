import 'package:flutter/material.dart';

import 'package:scheduling/core/animations/animated_form_field_wrapper.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/animations/fade_slide_entrance.dart';
import 'package:scheduling/core/animations/staggered_entrance_controller.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/features/auth/data/auth_error_mapper.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';

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

class _CreateAccountScreenState extends State<CreateAccountScreen>
    with SingleTickerProviderStateMixin {
  static const int _itemCount = 8;

  late final AuthService _authService = widget.authService ?? AuthService();
  late final TextEditingController _emailController;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();

  late final StaggeredEntranceController _entrance;

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
    _entrance = StaggeredEntranceController(vsync: this, itemCount: _itemCount)
      ..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
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
      });
      _entrance.controller.forward(from: 0);
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
    return WillPopScope(
      onWillPop: () async {
        _backToSignIn();
        return false;
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
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;
    final animations = _entrance.animations;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeSlideEntrance(
          animation: animations[0],
          child: Container(
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
        ),
        const SizedBox(height: AppSpacing.sp24),
        FadeSlideEntrance(
          animation: animations[1],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.auth_createAccount, style: textTheme.headlineLarge),
              const SizedBox(height: 4),
              Text(
                context.l10n.auth_useTheEmailYourAdminAddedToTheEmployeeList,
                style: textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sp32),
        FadeSlideEntrance(
          animation: animations[2],
          child: AnimatedFormFieldWrapper(
            hasError: _emailError != null,
            child: TextField(
              controller: _emailController,
              focusNode: _emailFocus,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.email],
              enabled: !_isLoading,
              onSubmitted: (_) => _passwordFocus.requestFocus(),
              onChanged: (_) => _onFieldChanged(),
              decoration: formInputDecoration(context, context.l10n.common_email)
                  .copyWith(
                    errorText: _emailError,
                    prefixIcon: const Icon(Icons.email_outlined, size: 20),
                  ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        FadeSlideEntrance(
          animation: animations[3],
          child: AnimatedFormFieldWrapper(
            hasError: _passwordError != null,
            child: TextField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              obscureText: _isObscured,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              enabled: !_isLoading,
              onSubmitted: (_) => _confirmPasswordFocus.requestFocus(),
              onChanged: (_) => _onFieldChanged(),
              decoration: formInputDecoration(context, context.l10n.common_password)
                  .copyWith(
                    errorText: _passwordError,
                    prefixIcon: const Icon(Icons.lock_outlined, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isObscured
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      tooltip: _isObscured
                          ? context.l10n.auth_showPassword
                          : context.l10n.auth_hidePassword,
                      onPressed: () =>
                          setState(() => _isObscured = !_isObscured),
                    ),
                  ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        FadeSlideEntrance(
          animation: animations[4],
          child: AnimatedFormFieldWrapper(
            hasError: _confirmPasswordError != null,
            child: TextField(
              controller: _confirmPasswordController,
              focusNode: _confirmPasswordFocus,
              obscureText: _isConfirmObscured,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              enabled: !_isLoading,
              onSubmitted: (_) => _createAccount(),
              onChanged: (_) => _onFieldChanged(),
              decoration:
                  formInputDecoration(
                    context,
                    context.l10n.auth_confirmPassword,
                  ).copyWith(
                    errorText: _confirmPasswordError,
                    prefixIcon: const Icon(Icons.lock_reset_outlined, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isConfirmObscured
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      tooltip: _isConfirmObscured
                          ? context.l10n.auth_showPassword
                          : context.l10n.auth_hidePassword,
                      onPressed: () => setState(
                        () => _isConfirmObscured = !_isConfirmObscured,
                      ),
                    ),
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
          child: _bannerError != null
              ? Padding(
                  key: ValueKey('err_$_bannerError'),
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
                            _bannerError!,
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
        ),
        const SizedBox(height: AppSpacing.sp24),
        FadeSlideEntrance(
          animation: animations[5],
          child: AnimatedLoadingButton(
            label: context.l10n.auth_createAccount,
            isLoading: _isLoading,
            onPressed: _createAccount,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        FadeSlideEntrance(
          animation: animations[6],
          child: Center(
            child: TextButton(
              onPressed: _isLoading ? null : _backToSignIn,
              child: Text(
                context.l10n.auth_backToSignIn,
                style: textTheme.bodySmall?.copyWith(color: scheme.primary),
              ),
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
    final animations = _entrance.animations;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1).animate(animations[0]),
          child: FadeTransition(
            opacity: animations[0],
            child: Container(
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
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sp24),
        FadeSlideEntrance(
          animation: animations[1],
          child: Text(
            context.l10n.auth_accountCreated,
            style: textTheme.headlineLarge,
          ),
        ),
        const SizedBox(height: 4),
        FadeSlideEntrance(
          animation: animations[2],
          child: Text(
            context.l10n.auth_youCanNowSignInWithThisEmailAndPassword,
            style: textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.sp32),
        FadeSlideEntrance(
          animation: animations[3],
          child: AnimatedLoadingButton(
            label: context.l10n.auth_backToSignIn,
            onPressed: _backToSignIn,
          ),
        ),
      ],
    );
  }
}
