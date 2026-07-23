import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shakes [child] horizontally when [hasError] flips from false to true
/// (one sine cycle of ±6px over 320ms, matching the old flutter_animate shakeX).
class AnimatedFormFieldWrapper extends StatefulWidget {
  const AnimatedFormFieldWrapper({
    required this.child,
    super.key,
    this.hasError = false,
  });

  final Widget child;
  final bool hasError;

  @override
  State<AnimatedFormFieldWrapper> createState() =>
      _AnimatedFormFieldWrapperState();
}

class _AnimatedFormFieldWrapperState extends State<AnimatedFormFieldWrapper>
    with SingleTickerProviderStateMixin {
  static const double _amount = 6;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void didUpdateWidget(covariant AnimatedFormFieldWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // NOTE: reduced-motion is intentionally evaluated only at the error
    // transition; an in-flight 320ms shake isn't worth interrupting.
    if (widget.hasError &&
        !oldWidget.hasError &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.translate(
        offset: Offset(math.sin(_controller.value * math.pi * 2) * _amount, 0),
        child: child,
      ),
      child: widget.child,
    );
  }
}
