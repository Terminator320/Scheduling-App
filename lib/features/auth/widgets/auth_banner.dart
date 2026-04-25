import 'package:flutter/material.dart';

enum AuthBannerKind { error, success, info }

class AuthBanner extends StatelessWidget {
  const AuthBanner({
    super.key,
    required this.message,
    this.kind = AuthBannerKind.info,
  });

  final String message;
  final AuthBannerKind kind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color accent;
    final Color background;
    final IconData icon;

    switch (kind) {
      case AuthBannerKind.error:
        accent = scheme.error;
        background = scheme.error.withAlpha(22);
        icon = Icons.error_outline_rounded;
        break;
      case AuthBannerKind.success:
        accent = scheme.secondary;
        background = scheme.secondary.withAlpha(38);
        icon = Icons.check_circle_rounded;
        break;
      case AuthBannerKind.info:
        accent = scheme.primary;
        background = scheme.primary.withAlpha(22);
        icon = Icons.info_outline_rounded;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withAlpha(60), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
