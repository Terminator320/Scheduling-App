import 'package:flutter/material.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/widgets/tour_step_text.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:showcaseview/showcaseview.dart';

/// One step of a tab's feature tour: wraps the highlighted widget in a themed
/// [Showcase] (design: Option A anchored tooltip — see
/// docs/plans/2026-07-22-feature-tour-design.md). [index]/[count] come from
/// the tab's `tourStepsFor` catalog so the counter matches the tour order.
class TourShowcase extends StatelessWidget {
  const TourShowcase({
    required this.showcaseKey,
    required this.tab,
    required this.id,
    required this.index,
    required this.count,
    required this.child,
    this.targetBorderRadius,
    super.key,
  });

  final GlobalKey showcaseKey;
  final AdaptiveDestination tab;
  final TourStepId id;
  final int index;
  final int count;

  /// Rounding of the lit target cutout; defaults to r12 (cards/tiles). FABs
  /// pass r16 to match their shape.
  final BorderRadius? targetBorderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = tourStepText(context.l10n, id);
    final noMotion = MediaQuery.disableAnimationsOf(context);
    return Showcase(
      key: showcaseKey,
      scope: tourScopeName(tab),
      title: text.title,
      description: text.description,
      titleTextStyle: theme.textTheme.titleMedium?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      descTextStyle: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      tooltipBackgroundColor: scheme.surface,
      tooltipBorderRadius: BorderRadius.circular(AppRadius.r16),
      tooltipPadding: const EdgeInsets.all(AppSpacing.sp16),
      targetBorderRadius:
          targetBorderRadius ?? BorderRadius.circular(AppRadius.r12),
      targetPadding: const EdgeInsets.all(AppSpacing.sp4),
      overlayColor: scheme.scrim,
      overlayOpacity: 0.62,
      disableMovingAnimation: noMotion,
      disableScaleAnimation: noMotion,
      tooltipActionConfig: const TooltipActionConfig(
        position: TooltipActionPosition.inside,
        alignment: MainAxisAlignment.spaceBetween,
        actionGap: AppSpacing.sp8,
      ),
      tooltipActions: [
        TooltipActionButton.custom(
          button: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp8),
            child: Text(
              context.l10n.tour_stepCounter(index + 1, count),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        TooltipActionButton(
          type: TooltipDefaultActionType.skip,
          name: context.l10n.tour_skip,
          backgroundColor: Colors.transparent,
          textStyle: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        TooltipActionButton(
          type: TooltipDefaultActionType.next,
          name: context.l10n.tour_next,
          backgroundColor: scheme.primary,
          borderRadius: BorderRadius.circular(AppRadius.rFull),
          textStyle: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onPrimary,
          ),
        ),
      ],
      child: child,
    );
  }
}

/// [TourShowcase] adapter for `AppTopBar.bottom`, which requires a
/// [PreferredSizeWidget] — a bare Showcase wrapper would break the app-bar
/// layout contract.
class TourShowcaseBar extends StatelessWidget implements PreferredSizeWidget {
  const TourShowcaseBar({
    required this.showcaseKey,
    required this.tab,
    required this.id,
    required this.index,
    required this.count,
    required this.bar,
    super.key,
  });

  final GlobalKey showcaseKey;
  final AdaptiveDestination tab;
  final TourStepId id;
  final int index;
  final int count;
  final PreferredSizeWidget bar;

  @override
  Size get preferredSize => bar.preferredSize;

  @override
  Widget build(BuildContext context) => TourShowcase(
    showcaseKey: showcaseKey,
    tab: tab,
    id: id,
    index: index,
    count: count,
    child: bar,
  );
}
