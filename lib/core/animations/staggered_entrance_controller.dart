import 'package:flutter/material.dart';

import 'package:scheduling/core/animations/app_animation_constants.dart';

class StaggeredEntranceController {
  StaggeredEntranceController({
    required TickerProvider vsync,
    required int itemCount,
    Duration duration = AppAnimationDurations.entrance,
  }) : controller = AnimationController(vsync: vsync, duration: duration) {
    animations = List.generate(itemCount, (index) {
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
