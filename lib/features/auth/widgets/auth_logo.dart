import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

/// The square branded app mark shown at the top of every auth screen
/// (sign-in, create-account, forgot-password).
class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Icon(
        Icons.calendar_today_rounded,
        color: scheme.onPrimary,
        size: 22,
      ),
    );
  }
}
