import 'package:flutter/material.dart';

import 'app_animation_constants.dart';
import 'tap_scale.dart';

enum AnimatedLoadingButtonVariant { filled, outlined }

class AnimatedLoadingButton extends StatelessWidget {
  const AnimatedLoadingButton({
    super.key,
    required this.label,
    required this.onPressed,
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
    // ValueKeys force AnimatedSwitcher to treat the spinner and label as
    // different widgets so it plays the crossfade when isLoading changes.
    final child = AnimatedSwitcher(
      duration: AppAnimationDurations.switcher,
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

    // TapScale adds a subtle press shrink; disabled when the button is blocked.
    return TapScale(
      enabled: effectiveOnPressed != null,
      child: SizedBox(
        height: height,
        child: variant == AnimatedLoadingButtonVariant.filled
            ? FilledButton(
                onPressed: effectiveOnPressed,
                style: FilledButton.styleFrom(shape: shape),
                child: child,
              )
            : OutlinedButton(
                onPressed: effectiveOnPressed,
                style: OutlinedButton.styleFrom(shape: shape),
                child: child,
              ),
      ),
    );
  }
}
