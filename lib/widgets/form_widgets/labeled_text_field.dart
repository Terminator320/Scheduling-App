import 'package:flutter/material.dart';
import 'form_helpers.dart';

class LabeledTextField extends StatelessWidget {
  const LabeledTextField({
    super.key,
    required this.label,
    required this.controller,
    this.required = false,
    this.optional = false,
    this.keyboard = TextInputType.text,
    this.autofillHints,
    this.maxLines = 1,
    this.readOnly = false,
    this.onTap,
    this.onChanged,
    this.suffixIcon,
    this.prefixIcon,
    this.hint,
    this.errorText,
  });

  final String label;
  final TextEditingController controller;
  final bool required;
  final bool optional;
  final TextInputType keyboard;
  final Iterable<String>? autofillHints;
  final int maxLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final String? hint;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final displayLabel = required ? "$label *" : label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        formLabel(context, displayLabel, optional: optional),
        TextField(
          controller: controller,
          keyboardType: keyboard,
          autofillHints: autofillHints,
          maxLines: maxLines,
          readOnly: readOnly,
          onTap: onTap,
          onChanged: onChanged,
          decoration: formInputDecoration(context, hint ?? label).copyWith(
            errorText: errorText,
            suffixIcon: suffixIcon,
            prefixIcon: prefixIcon,
          ),
        ),
      ],
    );
  }
}
