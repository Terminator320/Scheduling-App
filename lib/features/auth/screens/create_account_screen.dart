import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:scheduling/core/animations/animated_form_field_wrapper.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/animations/fade_slide_entrance.dart';
import 'package:scheduling/core/animations/staggered_entrance_controller.dart';
import 'package:scheduling/core/errors/auth_error_handler.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/auth/widgets/auth_banner.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';

class CreateAccountResult {
  const CreateAccountResult({required this.created, this.email});

  final bool created;
  final String? email;
}

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen>
    with SingleTickerProviderStateMixin {
  static const int _itemCount = 8;

  final AuthService _authService = AuthService();
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
      confirmErr = context.l10n.pleaseConfirmYourPassword;
    } else if (_confirmPasswordController.text.trim() !=
        _passwordController.text.trim()) {
      confirmErr = context.l10n.passwordsDoNotMatch;
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
      setState(() {
        _bannerError = AuthErrorHandler.getMessage(
          context,
          error,
          authContext: AuthErrorContext.register,
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
    final colour = Theme.of(context).colorScheme;

    return WillPopScope(
      onWillPop: () async {
        _backToSignIn();
        return false;
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(FontAwesomeIcons.arrowLeft),
              tooltip: context.l10n.back,
              onPressed: _isLoading ? null : _backToSignIn,
            ),
            title: Text(context.l10n.createAccount2),
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
                      child: _created
                          ? _buildSuccess(key: const ValueKey('success'))
                          : _buildForm(key: const ValueKey('form')),
                    ),
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
                  FontAwesomeIcons.userPlus,
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
                context.l10n.createAccount2,
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.useTheEmailYourAdminAddedToTheEmployeeList,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colour.onSurface.withAlpha(150),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
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
              decoration: formInputDecoration(
                context,
                context.l10n.email,
              ).copyWith(
                errorText: _emailError,
                prefixIcon: const Icon(FontAwesomeIcons.envelope, size: 20),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
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
              decoration: formInputDecoration(
                context,
                context.l10n.password,
              ).copyWith(
                errorText: _passwordError,
                prefixIcon: const Icon(FontAwesomeIcons.lock, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isObscured
                        ? FontAwesomeIcons.eyeSlash
                        : FontAwesomeIcons.eye,
                    size: 20,
                  ),
                  tooltip: _isObscured
                      ? context.l10n.showPassword
                      : context.l10n.hidePassword,
                  onPressed: () => setState(() => _isObscured = !_isObscured),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
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
              decoration: formInputDecoration(
                context,
                context.l10n.confirmPassword,
              )
                  .copyWith(
                    errorText: _confirmPasswordError,
                    prefixIcon: const Icon(FontAwesomeIcons.lock, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isConfirmObscured
                            ? FontAwesomeIcons.eyeSlash
                            : FontAwesomeIcons.eye,
                        size: 20,
                      ),
                      tooltip: _isConfirmObscured
                          ? context.l10n.showPassword
                          : context.l10n.hidePassword,
                      onPressed: () => setState(
                        () => _isConfirmObscured = !_isConfirmObscured,
                      ),
                    ),
                  ),
            ),
          ),
        ),
        const SizedBox(height: 18),
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
                  padding: const EdgeInsets.only(bottom: 14),
                  child: AuthBanner(
                    kind: AuthBannerKind.error,
                    message: _bannerError!,
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('banner_none')),
        ),
        FadeSlideEntrance(
          animation: animations[5],
          child: AnimatedLoadingButton(
            label: context.l10n.createAccount,
            isLoading: _isLoading,
            onPressed: _createAccount,
          ),
        ),
        const SizedBox(height: 14),
        FadeSlideEntrance(
          animation: animations[6],
          child: TextButton(
            onPressed: _isLoading ? null : _backToSignIn,
            child: Text(context.l10n.backToSignIn),
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
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: colour.primary.withAlpha(28),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  FontAwesomeIcons.circleCheck,
                  size: 42,
                  color: colour.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        FadeSlideEntrance(
          animation: animations[1],
          child: Text(
            context.l10n.accountCreated,
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        FadeSlideEntrance(
          animation: animations[2],
          child: Text(
            context.l10n.youCanNowSignInWithThisEmailAndPassword,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: colour.onSurface.withAlpha(150),
            ),
          ),
        ),
        const SizedBox(height: 28),
        FadeSlideEntrance(
          animation: animations[3],
          child: AnimatedLoadingButton(
            label: context.l10n.backToSignIn,
            isLoading: false,
            onPressed: _backToSignIn,
          ),
        ),
      ],
    );
  }
}
