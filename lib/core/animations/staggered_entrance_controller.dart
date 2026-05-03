import 'package:flutter/material.dart';

import 'app_animation_constants.dart';

// Drives N staggered animations from a single AnimationController.
// Call forward() once; each item in [animations] plays at its own offset
// within the shared timeline defined by AppStagger constants.
class StaggeredEntranceController {
  StaggeredEntranceController({
    required TickerProvider vsync,
    required int itemCount,
    Duration duration = AppAnimationDurations.entrance,
  }) : controller = AnimationController(vsync: vsync, duration: duration) {
    animations = List.generate(itemCount, (index) {
      // Interval maps this item's slice of [0..1] → its own 0→1 progress.
      final start = (index * AppStagger.delay).clamp(0.0, 1.0);
      final end = (start + AppStagger.itemDuration).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: controller,
        curve: Interval(start, end, curve: AppAnimationCurves.entrance),
      );
    });
  }

  final AnimationController controller;
  late final List<Animation<double>> animations;

  void forward() => controller.forward();

  void dispose() => controller.dispose();
}
