import 'package:flutter/material.dart';

class InfoRow extends StatelessWidget {

  const InfoRow({
    required this.icon, required this.text, super.key,
    this.textStyle,
    this.iconColor,
  });
  final IconData icon;
  final String text;
  final TextStyle? textStyle;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              size: 16,
              color: iconColor ?? scheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: textStyle ?? theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
