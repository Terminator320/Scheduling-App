import 'package:flutter/material.dart';

import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/animations/tap_scale.dart';

enum AnimatedLoadingButtonVariant { filled, outlined }

class AnimatedLoadingButton extends StatelessWidget {
  const AnimatedLoadingButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.isLoading = false,
    this.variant = AnimatedLoadingButtonVariant.filled,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final AnimatedLoadingButtonVariant variant;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final effectiveOnPressed = isLoading ? null : onPressed;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final child = AnimatedSwitcher(
      duration: AppAnimationDurations.switcher,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
      child: isLoading
          ? SizedBox(
              key: const ValueKey('spinner'),
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: variant == AnimatedLoadingButtonVariant.filled
                    ? colour.onPrimary
                    : colour.primary,
              ),
            )
          : Text(
              key: const ValueKey('label'),
              label,
              style: textTheme.titleSmall?.copyWith(
                color: variant == AnimatedLoadingButtonVariant.filled
                    ? colour.onPrimary
                    : colour.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
    );

    // Use minHeight (not fixed height) so the label can grow with the user's
    // text scale instead of being clipped. At 1.4×/2.0× the scaled label
    // height ends up taller than the default 52, and a hard SizedBox(height:)
    // visually crops the text without raising a RenderFlex overflow.
    return TapScale(
      enabled: effectiveOnPressed != null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: variant == AnimatedLoadingButtonVariant.filled
            ? FilledButton(
                onPressed: effectiveOnPressed,
                style: FilledButton.styleFrom(
                  shape: shape,
                  minimumSize: Size.fromHeight(height),
                ),
                child: child,
              )
            : OutlinedButton(
                onPressed: effectiveOnPressed,
                style: OutlinedButton.styleFrom(
                  shape: shape,
                  minimumSize: Size.fromHeight(height),
                ),
                child: child,
              ),
      ),
    );
  }
}
