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
    // Honor reduce-motion; show static color instead of shimmer.
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
                // NOTE: 11/9 are shimmer line heights, not spacing — kept literal to size the bars.
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
                // NOTE: 11/9 are shimmer line heights, not spacing — kept literal to size the bars.
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
