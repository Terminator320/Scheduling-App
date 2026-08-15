import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// The "jump to today" pill. It scales and fades out once today is already in
/// view, staying mounted so the transition is animated both ways.
class TodayPill extends StatelessWidget {
  const TodayPill({
    required this.visible,
    required this.onPressed,
    super.key,
  });

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instant = MediaQuery.disableAnimationsOf(context);
    final radius = BorderRadius.circular(AppRadius.rFull);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1 : 0.85,
        duration: instant ? Duration.zero : AppMotion.popIn,
        curve: AppMotion.emphasized,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: instant ? Duration.zero : AppMotion.popIn,
          child: Tooltip(
            message: context.l10n.calendar_today,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: theme.cardStyle.pillShadow,
              ),
              child: Material(
                color: theme.colorScheme.surface,
                borderRadius: radius,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sp16,
                        vertical: 11,
                      ),
                      child: Center(
                        child: Text(
                          context.l10n.calendar_today,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.palette.primaryAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
