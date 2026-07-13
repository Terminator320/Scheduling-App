import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scheduling/core/animations/animated_form_field_wrapper.dart';
import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/clear_text_button.dart';
import 'package:scheduling/shared/widgets/fields/dictation_listening_bar.dart';
import 'package:scheduling/shared/widgets/fields/dictation_mic_button.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';

class LabeledTextField extends StatefulWidget {
  const LabeledTextField({
    required this.label,
    required this.controller,
    super.key,
    this.required = false,
    this.optional = false,
    this.keyboard = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.autofillHints,
    this.maxLines = 1,
    this.maxLength,
    this.showCounter = false,
    this.readOnly = false,
    this.enableDictation = false,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
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
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final int maxLines;

  final int? maxLength;
  final bool showCounter;
  final bool readOnly;

  /// Opt-in: adds a dictation mic to the suffix (beside the clear "x") and a
  /// live listening bar below the field while dictating. Ignored on readOnly
  /// fields or when a custom [suffixIcon] is supplied.
  final bool enableDictation;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final String? hint;
  final String? errorText;
  final FocusNode? focusNode;

  @override
  State<LabeledTextField> createState() => _LabeledTextFieldState();
}

class _LabeledTextFieldState extends State<LabeledTextField> {
  ValueNotifier<bool>? _listening;

  bool get _dictationActive =>
      widget.enableDictation && !widget.readOnly && widget.suffixIcon == null;

  @override
  void initState() {
    super.initState();
    if (_dictationActive) _listening = ValueNotifier<bool>(false);
  }

  @override
  void dispose() {
    _listening?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        formLabel(
          context,
          widget.label,
          optional: widget.optional,
          required: widget.required,
        ),
        AnimatedFormFieldWrapper(
          hasError: widget.errorText != null,
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            keyboardType: widget.keyboard,
            textCapitalization: widget.textCapitalization,
            textInputAction: widget.textInputAction,
            autofillHints: widget.autofillHints,
            maxLines: widget.maxLines,
            onSubmitted: widget.onSubmitted,
            // With showCounter, TextField.maxLength enforces the cap and
            // renders the live "x/y" counter; otherwise enforce silently.
            maxLength: widget.showCounter ? widget.maxLength : null,
            inputFormatters: widget.maxLength == null || widget.showCounter
                ? null
                : [LengthLimitingTextInputFormatter(widget.maxLength)],
            readOnly: widget.readOnly,
            onTap: widget.onTap,
            onChanged: widget.onChanged,
            decoration:
                formInputDecoration(
                  context,
                  widget.hint ?? widget.label,
                ).copyWith(
                  errorText: widget.errorText != null ? '' : null,
                  errorStyle: const TextStyle(fontSize: 0, height: 0),
                  // Every editable field gets a clear "x" while it holds
                  // text; a custom suffix or a readOnly (picker) field
                  // keeps its own. enableDictation prepends a mic.
                  suffixIcon: widget.suffixIcon ?? _defaultSuffix(),
                  prefixIcon: widget.prefixIcon,
                ),
          ),
        ),
        if (_listening != null) _listeningBar(),
        if (widget.showCounter && widget.maxLength != null)
          _MaxLengthWarning(
            controller: widget.controller,
            maxLength: widget.maxLength!,
          ),
        _AnimatedFieldError(message: widget.errorText),
      ],
    );
  }

  Widget? _defaultSuffix() {
    if (widget.readOnly) return null;
    final clear = ClearTextButton(
      controller: widget.controller,
      onCleared: () => widget.onChanged?.call(''),
    );
    if (!_dictationActive) return clear;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DictationMicButton(
          controller: widget.controller,
          onChanged: widget.onChanged,
          maxLength: widget.maxLength,
          listening: _listening,
        ),
        clear,
      ],
    );
  }

  // The bar exists only while listening; AnimatedSize slides it in/out and the
  // fields below glide instead of jumping (matches the field-error entrance).
  Widget _listeningBar() {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppAnimationDurations.quick;
    return ValueListenableBuilder<bool>(
      valueListenable: _listening!,
      builder: (context, listening, _) => AnimatedSize(
        duration: duration,
        curve: AppAnimationCurves.entrance,
        alignment: Alignment.topCenter,
        child: listening
            ? const DictationListeningBar()
            : const SizedBox(width: double.infinity),
      ),
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
