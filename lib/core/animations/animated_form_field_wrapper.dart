import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

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

class _AnimatedFormFieldWrapperState extends State<AnimatedFormFieldWrapper> {
  int _shakeTick = 0;

  @override
  void didUpdateWidget(covariant AnimatedFormFieldWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasError && !oldWidget.hasError) {
      _shakeTick++;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child
        .animate(key: ValueKey(_shakeTick))
        .shakeX(duration: 320.ms, hz: 3, amount: 6);
  }
}
