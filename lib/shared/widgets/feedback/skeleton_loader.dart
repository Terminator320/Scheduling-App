import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

class _SkeletonBox extends StatefulWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    this.borderRadius,
  });

  final double width;
  final double height;
  final double? borderRadius;

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: AppDuration.shimmer,
  );
  late final Animation<double> _anim = Tween<double>(
    begin: -2,
    end: 2,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.linear));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honor reduce-motion by showing a static color instead of the shimmer.
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final highlight = scheme.outline;
    final borderRadius = BorderRadius.circular(
      widget.borderRadius ?? AppRadius.r8,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(borderRadius: borderRadius, color: base),
      );
    }
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value + 1, 0),
            colors: [base, highlight, base],
          ),
        ),
      ),
    );
  }
}

class SkeletonAppointmentRow extends StatelessWidget {
  const SkeletonAppointmentRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sp8),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp12,
        vertical: AppSpacing.sp8 + 2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r8),
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 3,
          ),
        ),
        boxShadow: AppShadow.card,
      ),
      child: const Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 11 and 9 here are shimmer line heights, not spacing values
                // — kept literal so the bars come out the right size.
                _SkeletonBox(width: 130, height: 11),
                SizedBox(height: AppSpacing.sp4),
                _SkeletonBox(width: 90, height: 9),
              ],
            ),
          ),
          _SkeletonBox(width: 62, height: 20, borderRadius: AppRadius.rFull),
        ],
      ),
    );
  }
}

/// [rows] stacked [SkeletonListTile]s — the standard loading state for a list.
///
/// Deliberately NOT scrollable: two of its three callers sit inside
/// `infinite_scroll_pagination`'s `SliverFillRemaining`, which asks its child
/// for intrinsic dimensions, and a nested `ListView` there throws.
///
/// This was hand-built at each call site and had already drifted — the Team
/// roster used a `sp12` gap where the other two used `sp8`, so the same
/// loading state rendered at two different rhythms.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    this.rows = 3,
    this.padding = const EdgeInsets.all(AppSpacing.sp16),
    super.key,
  });

  final int rows;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sp8),
          const SkeletonListTile(),
        ],
      ],
    ),
  );
}

class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sp8),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp12,
        vertical: AppSpacing.sp8 + 2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r8),
        boxShadow: AppShadow.card,
      ),
      child: const Row(
        children: [
          _SkeletonBox(width: 36, height: 36, borderRadius: AppRadius.rFull),
          SizedBox(width: AppSpacing.sp12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 11 and 9 here are shimmer line heights, not spacing values
                // — kept literal so the bars come out the right size.
                _SkeletonBox(width: 110, height: 11),
                SizedBox(height: AppSpacing.sp4),
                _SkeletonBox(width: 75, height: 9),
              ],
            ),
          ),
          _SkeletonBox(width: 52, height: 20, borderRadius: AppRadius.rFull),
        ],
      ),
    );
  }
}
