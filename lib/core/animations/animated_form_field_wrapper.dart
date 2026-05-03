import 'dart:math' as math;

import 'package:flutter/material.dart';

class AnimatedFormFieldWrapper extends StatefulWidget {
  const AnimatedFormFieldWrapper({
    super.key,
    required this.child,
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
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedFormFieldWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasError && !oldWidget.hasError) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        // Damped sine: a small left-right nudge that fades out quickly.
        final t = _shake.value;
        final dx = t == 0
            ? 0.0
            : math.sin(t * math.pi * 3) * 6 * (1 - t);
        return Transform.translate(
          offset: Offset(dx, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
