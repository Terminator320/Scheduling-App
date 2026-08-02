import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:scheduling/core/animations/animated_form_field_wrapper.dart';
import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/branding/brand_logo.dart';
import 'package:scheduling/shared/widgets/fields/clear_text_button.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';

/// Shared form components for all auth screens, consolidating duplicated per-screen widgets.

/// The gradient block at the top of an auth screen. [thin] drops the brand
/// mark for the secondary screens, which lead with their own title.
class AuthHero {
  const AuthHero({
    required this.title,
    required this.subtitle,
    this.thin = false,
  });

  final String title;
  final String subtitle;
  final bool thin;
}

/// Outer shell for auth forms: keyboard dismissal, standard padding,
/// [AutofillGroup] for OS password managers. With a [hero] the form rides in a
/// lifted card overlapping the gradient block; without one the child sits
/// straight on the surface.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({required this.child, this.hero, this.footer, super.key});

  /// How far the card overlaps the hero block above it.
  static const double _cardLift = 28;

  final Widget child;
  final AuthHero? hero;

  /// Rendered below the card, outside its chrome (the sign-in invite prompt).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hero = this.hero;
    // Gradient.colors is on the base class, so this reads the token without
    // caring which gradient shape the palette carries.
    final heroInk = theme.palette.heroGradient.colors.last;

    // The hero is full-bleed behind the status bar and these screens have no
    // app bar, so nothing else sets the overlay style. Derived from the colour
    // actually behind the bar, not the theme brightness.
    final statusBarSurface = hero == null ? scheme.surface : heroInk;
    final overlay =
        ThemeData.estimateBrightnessForColor(statusBarSurface) ==
            Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    var card = child;
    if (hero != null) {
      card = DecoratedBox(
        decoration: appCardDecoration(
          theme,
          radius: AppRadius.r20,
          color: scheme.surface,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sp24),
          child: child,
        ),
      );
    }

    final footer = this.footer;
    // Fades and slides the whole form in on entrance. Under reduce-motion it
    // skips straight to the end state instead of animating.
    Widget content = AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card,
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.sp24),
            footer,
          ],
        ],
      ),
    );
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

    Widget body = Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sp24,
        hero == null ? AppSpacing.sp32 : 0,
        AppSpacing.sp24,
        AppSpacing.sp32,
      ),
      // Caps the width for tablets and landscape — this is a no-op on
      // phones narrower than 440.
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: content,
        ),
      ),
    );
    if (hero != null) {
      // Lifts the card over the hero. A negative EdgeInsets would assert, and
      // the extra slack this leaves lands harmlessly at the scroll bottom.
      body = Transform.translate(
        offset: const Offset(0, -_cardLift),
        child: body,
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: scheme.surface,
          body: SafeArea(
            // The hero paints behind the status bar and pads itself instead.
            top: hero == null,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hero != null)
                    _AuthHeroBlock(hero: hero, bottomGap: _cardLift),
                  body,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthHeroBlock extends StatelessWidget {
  const _AuthHeroBlock({required this.hero, required this.bottomGap});

  final AuthHero hero;
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradient = theme.palette.heroGradient;
    final foreground = contrastingForegroundFor(gradient.colors.last);
    final topInset = MediaQuery.paddingOf(context).top;

    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.sp24,
          topInset + (hero.thin ? AppSpacing.sp24 : AppSpacing.sp32),
          AppSpacing.sp24,
          AppSpacing.sp24 + bottomGap,
        ),
        child: Column(
          children: [
            if (!hero.thin) ...[
              const BrandMark(),
              const SizedBox(height: AppSpacing.sp16),
            ],
            Text(
              hero.title,
              style: theme.textTheme.headlineLarge?.copyWith(
                color: foreground,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sp4),
            Text(
              hero.subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foreground.withValues(alpha: 0.82),
              ),
              textAlign: TextAlign.center,
            ),
          ],
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

/// The error row beneath a bordered auth field — a red dot plus the message.
/// Lives in the decoration's error slot, so it also turns the border red.
class AuthFieldError extends StatelessWidget {
  const AuthFieldError({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            color: scheme.error,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.sp8),
        Flexible(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ),
      ],
    );
  }
}

/// Wraps [field] under an optional label, keeping labelled and unlabelled auth
/// fields on one layout.
Widget _labelledField(BuildContext context, String? label, Widget field) {
  if (label == null) return field;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [formLabel(context, label), field],
  );
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
    this.label,
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

  /// Rendered above the field; null keeps the bare hint-only layout.
  final String? label;
  final TextInputAction textInputAction;
  final VoidCallback onSubmitted;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final errorText = this.errorText;
    return _labelledField(
      context,
      label,
      AnimatedFormFieldWrapper(
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
                // A visible label already names the field, so the hint only
                // fills in when there is nothing above the box.
                hint ?? (label == null ? context.l10n.common_email : ''),
              ).copyWith(
                error: errorText == null
                    ? null
                    : AuthFieldError(message: errorText),
                prefixIcon: const Icon(Icons.email_outlined, size: 20),
                suffixIcon: ClearTextButton(
                  controller: controller,
                  onCleared: onChanged,
                ),
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
    this.showLabel = false,
    super.key,
  });

  final String label;

  /// Renders [label] above the field instead of only as the hint.
  final bool showLabel;
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
    final errorText = this.errorText;
    return _labelledField(
      context,
      showLabel ? label : null,
      AnimatedFormFieldWrapper(
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
          decoration: formInputDecoration(context, showLabel ? '' : label)
              .copyWith(
                error: errorText == null
                    ? null
                    : AuthFieldError(message: errorText),
                prefixIcon: Icon(prefixIcon, size: 20),
                // The Show/Hide link is small type — pin the 48px tap target
                // rather than inheriting whatever the platform density gives.
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: 48,
                ),
                suffixIcon: AnimatedSwitcher(
                  duration: AppAnimationDurations.quick,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: _ObscureToggleLink(
                    key: ValueKey(isObscured),
                    isObscured: isObscured,
                    onPressed: onToggleObscured,
                  ),
                ),
              ),
        ),
      ),
    );
  }
}

/// Show/Hide inside the password field: a mono uppercase text link, not an
/// icon button. The visible type is small, so the tap target is padded out to
/// the 48px minimum.
class _ObscureToggleLink extends StatelessWidget {
  const _ObscureToggleLink({
    required this.isObscured,
    required this.onPressed,
    super.key,
  });

  final bool isObscured;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final action = isObscured ? l10n.auth_showPassword : l10n.auth_hidePassword;
    return Tooltip(
      message: action,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.r8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sp12,
            vertical: AppSpacing.sp16,
          ),
          child: Semantics(
            label: action,
            excludeSemantics: true,
            child: Text(
              (isObscured ? l10n.auth_show : l10n.auth_hide).toUpperCase(),
              style: theme.monoType.label.copyWith(
                color: theme.palette.primaryAccent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
