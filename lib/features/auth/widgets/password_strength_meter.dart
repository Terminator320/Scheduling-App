import 'package:flutter/material.dart';

import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/password_strength.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Four segments driven by [passwordStrengthScore], plus the word for the band
/// it lands in — colour is never the only signal.
///
/// Advisory only: the submit gate is `AuthValidators.newPassword`, and the
/// requirements checklist beneath this meter is what tells the user what is
/// still missing.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({required this.password, super.key});

  static const int _segments = 4;
  static const double _barHeight = 5;

  final String password;

  @override
  Widget build(BuildContext context) {
    // Nothing typed yet — an empty meter reads as "weak" rather than "unrated".
    if (password.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = context.l10n;
    final score = passwordStrengthScore(password);
    final filled = _fillColor(theme, score);
    final label = _label(l10n, score);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppAnimationDurations.quick;

    return Semantics(
      label: l10n.auth_passwordStrengthSemantics(label),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var index = 0; index < _segments; index++) ...[
                if (index > 0) const SizedBox(width: AppSpacing.sp4),
                Expanded(
                  child: AnimatedContainer(
                    duration: duration,
                    height: _barHeight,
                    decoration: BoxDecoration(
                      color: index < score ? filled : theme.palette.track,
                      borderRadius: BorderRadius.circular(AppRadius.r8),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sp4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: filled),
          ),
        ],
      ),
    );
  }

  Color _fillColor(ThemeData theme, int score) => switch (score) {
    >= 4 => theme.statusColors.success,
    >= 2 => theme.statusColors.warning,
    _ => theme.colorScheme.error,
  };

  String _label(AppLocalizations l10n, int score) => switch (score) {
    >= 4 => l10n.auth_passwordStrengthStrong,
    3 => l10n.auth_passwordStrengthGood,
    2 => l10n.auth_passwordStrengthFair,
    _ => l10n.auth_passwordStrengthWeak,
  };
}
