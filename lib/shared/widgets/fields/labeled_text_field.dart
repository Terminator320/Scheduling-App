import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scheduling/core/animations/animated_form_field_wrapper.dart';
import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';

class LabeledTextField extends StatelessWidget {
  const LabeledTextField({
    required this.label,
    required this.controller,
    super.key,
    this.required = false,
    this.optional = false,
    this.keyboard = TextInputType.text,
    this.autofillHints,
    this.maxLines = 1,
    this.maxLength,
    this.showCounter = false,
    this.readOnly = false,
    this.onTap,
    this.onChanged,
    this.suffixIcon,
    this.prefixIcon,
    this.hint,
    this.errorText,
    this.focusNode,
  });

  final String label;
  final TextEditingController controller;
  final bool required;
  final bool optional;
  final TextInputType keyboard;
  final Iterable<String>? autofillHints;
  final int maxLines;

  final int? maxLength;
  final bool showCounter;
  final bool readOnly;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final String? hint;
  final String? errorText;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        formLabel(context, label, optional: optional, required: required),
        AnimatedFormFieldWrapper(
          hasError: errorText != null,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboard,
            autofillHints: autofillHints,
            maxLines: maxLines,
            // With showCounter, TextField.maxLength enforces the cap and
            // renders the live "x/y" counter; otherwise enforce silently.
            maxLength: showCounter ? maxLength : null,
            inputFormatters: maxLength == null || showCounter
                ? null
                : [LengthLimitingTextInputFormatter(maxLength)],
            readOnly: readOnly,
            onTap: onTap,
            onChanged: onChanged,
            decoration: formInputDecoration(context, hint ?? label).copyWith(
              errorText: errorText != null ? '' : null,
              errorStyle: const TextStyle(fontSize: 0, height: 0),
              suffixIcon: suffixIcon,
              prefixIcon: prefixIcon,
            ),
          ),
        ),
        if (showCounter && maxLength != null)
          _MaxLengthWarning(controller: controller, maxLength: maxLength!),
        _AnimatedFieldError(message: errorText),
      ],
    );
  }
}

class _MaxLengthWarning extends StatelessWidget {
  const _MaxLengthWarning({required this.controller, required this.maxLength});
  final TextEditingController controller;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => _AnimatedFieldError(
        // Grapheme count matches what TextField.maxLength enforces.
        message: value.text.characters.length < maxLength
            ? null
            : context.l10n.validation_maximumCharacterLimitReached,
      ),
    );
  }
}

// Fade + 4px slide entrance/exit for the error row (style A from the spec);
// AnimatedSize lets fields below glide instead of jumping.
class _AnimatedFieldError extends StatelessWidget {
  const _AnimatedFieldError({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppAnimationDurations.quick;
    return AnimatedSize(
      duration: duration,
      curve: AppAnimationCurves.entrance,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: AppAnimationCurves.entrance,
        switchOutCurve: AppAnimationCurves.entrance,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.25),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: message == null
            ? const SizedBox.shrink()
            : _FieldError(message!, key: ValueKey(message)),
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 11, color: error),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.labelSmall?.copyWith(
                color: error,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
