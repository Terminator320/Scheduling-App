import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';

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
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboard,
          autofillHints: autofillHints,
          maxLines: maxLines,
          inputFormatters: maxLength == null
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
        if (errorText != null) _FieldError(errorText!),
      ],
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
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
              style: TextStyle(fontSize: 11, color: error, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
