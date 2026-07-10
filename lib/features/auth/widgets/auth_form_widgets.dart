import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:scheduling/core/animations/animated_form_field_wrapper.dart';
import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/branding/brand_logo.dart';
import 'package:scheduling/shared/widgets/fields/clear_text_button.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';

/// Shared building blocks for the three auth screens (sign-in,
/// create-account, forgot-password). They were previously duplicated as
/// per-screen private widgets; consolidating them keeps the screens thin and
/// the form styling consistent.

/// The outer shell every auth screen shares: tap-to-dismiss keyboard, a
/// surface-colored [Scaffold], and a scroll view with the standard auth
/// padding. The form/success column goes in [child].
///
/// The [AutofillGroup] links the email + password fields into one OS autofill
/// context so password managers can fill both and — once the screen commits
/// via `TextInput.finishAutofillContext()` on success — offer to save them.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // One gentle entrance for the whole form (a single fade + small rise),
    // rather than staggering every field in separately. Collapses to instant
    // under the OS reduce-motion setting.
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
            // Cap the form width and center it so it reads as a tidy column on
            // tablets / landscape instead of fields stretched edge to edge.
            // Phones are narrower than the cap, so this is a no-op there.
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

/// Cross-fades + slides between an auth screen's form and its success state.
/// Used by create-account and forgot-password.
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

/// A centered headline + supporting line, the standard heading used under the
/// brand mark on each auth form and success panel. Full-width so it centers
/// across the form regardless of the parent column's cross-axis alignment.
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

/// The centered brand header shared by the three auth screens: the mascot mark
/// above a [AuthHeaderText]. Replaces the old left-aligned logo-badge +
/// heading stack.
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

/// A 44×44 rounded square holding a centered [icon]. Defaults to the primary
/// brand colors (the app mark); pass [background]/[foreground] for the
/// tertiary success variant.
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

/// The email input used by all three auth forms: a shake-on-error wrapper
/// around an email-keyboard [TextField] with the shared input decoration.
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

  /// Drives the shake animation. Defaults to `errorText != null`; sign-in
  /// passes it explicitly so the field can shake before the error text shows.
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

/// The obscurable password input used by the sign-in and create-account
/// forms, with an animated show/hide toggle.
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

/// A text input for a one-time code (signup code), styled to match the other
/// auth fields: shake-on-error, a key prefix icon, and the standard clear
/// button suffix.
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
