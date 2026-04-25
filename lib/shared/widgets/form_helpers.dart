import 'package:flutter/material.dart';

Widget formLabel(BuildContext context, String text, {bool optional = false}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Text(text, style: Theme.of(context).textTheme.labelMedium),
        if (optional)
          Text(
            " (optional)",
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    ),
  );
}

Widget formSectionLabel(BuildContext context, String text) {
  return Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

InputDecoration formInputDecoration(BuildContext context, String hint) {
  final scheme = Theme.of(context).colorScheme;
  return InputDecoration(
    hintText: hint,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: scheme.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: scheme.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: scheme.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: scheme.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: scheme.error, width: 1.5),
    ),
    filled: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}

Widget formRemoveButton(BuildContext context) {
  return Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.scrim.withOpacity(0.54),
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.close, size: 14, color: Colors.white),
  );
}
