import 'package:flutter/material.dart';

class FadeSlideEntrance extends StatelessWidget {
  const FadeSlideEntrance({
    required this.animation, required this.child, super.key,
    this.beginOffset = const Offset(0, 0.28),
  });

  final Animation<double> animation;
  final Widget child;
  final Offset beginOffset;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: beginOffset,
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}
