import 'package:flutter/material.dart';

import 'app_animation_constants.dart';

class TapScale extends StatefulWidget {
  const TapScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.97,
  });

  final Widget child;
  final bool enabled;
  final double pressedScale;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (!mounted || !widget.enabled) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    // Listener is used instead of GestureDetector so the press state is tracked
    // without consuming the tap gesture from the wrapped button.
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed && widget.enabled ? widget.pressedScale : 1,
        duration: AppAnimationDurations.tap,
        curve: AppAnimationCurves.tap,
        child: widget.child,
      ),
    );
  }
}
