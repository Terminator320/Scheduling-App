import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:scheduling/core/animations/animated_form_field_wrapper.dart';
import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/branding/brand_logo.dart';
import 'package:scheduling/shared/widgets/fields/clear_text_button.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';

/// Shared form components for all auth screens, consolidating duplicated per-screen widgets.

/// Outer shell for auth forms: keyboard dismissal, standard padding, [AutofillGroup] for OS password managers.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Fade + rise entrance for the whole form; collapses to instant under reduce-motion.
    Widget content = AutofillGroup(child: child);
    if (!MediaQuery.disableAnimationsOf(context)) {
      content = content
          .animate()
          .fadeIn(duration: 360.ms, curve: Curves.easeOut)
          .slideY(
            begin: 0.04,
            end: 0,
            duration: 360.ms,
            curve: AppAnimationCurves.entrance,
          );
    }

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
            // Cap width for tablets/landscape; no-op on phones narrower than 440.
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animates between form and success state via fade + slide.
class AuthFormSwitcher extends StatelessWidget {
  const AuthFormSwitcher({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
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
      child: child,
    );
  }
}

/// Centered headline + subtitle for auth forms, centered full-width below the brand mark.
class AuthHeaderText extends StatelessWidget {
  const AuthHeaderText({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          Text(
            title,
            style: theme.textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sp4),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Centered brand header for auth screens: mascot mark above headline + subtitle.
class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const BrandMark(size: 84),
        const SizedBox(height: AppSpacing.sp16),
        AuthHeaderText(title: title, subtitle: subtitle),
      ],
    );
  }
}

/// 44×44 rounded square holding a centered icon, defaulting to primary brand colors.
class AuthIconBadge extends StatelessWidget {
  const AuthIconBadge({
    required this.icon,
    this.background,
    this.foreground,
    super.key,
  });

  final IconData icon;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: background ?? scheme.primary,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Icon(icon, color: foreground ?? scheme.onPrimary, size: 22),
    );
  }
}

/// Email input with shake-on-error and clear button, used by all auth forms.
class AuthEmailField extends StatelessWidget {
  const AuthEmailField({
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
    required this.onChanged,
    this.focusNode,
    this.errorText,
    this.hasError,
    this.hint,
    this.textInputAction = TextInputAction.next,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final String? errorText;

  /// Drives shake animation; defaults to `errorText != null`.
  final bool? hasError;
  final String? hint;
  final TextInputAction textInputAction;
  final VoidCallback onSubmitted;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedFormFieldWrapper(
      hasError: hasError ?? errorText != null,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.emailAddress,
        textInputAction: textInputAction,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.email],
        enabled: enabled,
        onSubmitted: (_) => onSubmitted(),
        onChanged: (_) => onChanged(),
        decoration:
            formInputDecoration(
              context,
              hint ?? context.l10n.common_email,
            ).copyWith(
              errorText: errorText,
              prefixIcon: const Icon(Icons.email_outlined, size: 20),
              suffixIcon: ClearTextButton(
                controller: controller,
                onCleared: onChanged,
              ),
            ),
      ),
    );
  }
}

/// Password input with animated show/hide toggle for sign-in and account creation.
class AuthPasswordField extends StatelessWidget {
  const AuthPasswordField({
    required this.label,
    required this.controller,
    required this.enabled,
    required this.isObscured,
    required this.onSubmitted,
    required this.onChanged,
    required this.onToggleObscured,
    this.focusNode,
    this.errorText,
    this.hasError,
    this.prefixIcon = Icons.lock_outlined,
    this.textInputAction = TextInputAction.done,
    this.autofillHints = const [AutofillHints.password],
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final String? errorText;
  final bool? hasError;
  final IconData prefixIcon;
  final TextInputAction textInputAction;
  final List<String> autofillHints;
  final bool isObscured;
  final VoidCallback onSubmitted;
  final VoidCallback onChanged;
  final VoidCallback onToggleObscured;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedFormFieldWrapper(
      hasError: hasError ?? errorText != null,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: isObscured,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        enabled: enabled,
        onSubmitted: (_) => onSubmitted(),
        onChanged: (_) => onChanged(),
        decoration: formInputDecoration(context, label).copyWith(
          errorText: errorText,
          prefixIcon: Icon(prefixIcon, size: 20),
          suffixIcon: AnimatedSwitcher(
            duration: AppAnimationDurations.quick,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.7, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: IconButton(
              key: ValueKey(isObscured),
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
      ),
    );
  }
}

/// One-time code input with shake-on-error and clear button.
class AuthCodeField extends StatelessWidget {
  const AuthCodeField({
    required this.label,
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
    required this.onChanged,
    this.focusNode,
    this.errorText,
    this.maxLength,
    this.textInputAction = TextInputAction.done,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final String? errorText;
  final int? maxLength;
  final TextInputAction textInputAction;
  final VoidCallback onSubmitted;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedFormFieldWrapper(
      hasError: errorText != null,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: textInputAction,
        autocorrect: false,
        enableSuggestions: false,
        maxLength: maxLength,
        buildCounter: maxLength != null
            ? (_, {required currentLength, required isFocused, maxLength}) =>
                  null
            : null,
        enabled: enabled,
        onSubmitted: (_) => onSubmitted(),
        onChanged: (_) => onChanged(),
        decoration: formInputDecoration(context, label).copyWith(
          errorText: errorText,
          prefixIcon: const Icon(Icons.key_outlined, size: 20),
          suffixIcon: ClearTextButton(
            controller: controller,
            onCleared: onChanged,
          ),
        ),
      ),
    );
  }
}
