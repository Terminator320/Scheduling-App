import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';

/// Platform-adaptive busy spinner: `CupertinoActivityIndicator` on iOS,
/// `CircularProgressIndicator` on Android. Both render at [size] and honour
/// [color], so in-button brand spinners keep their colour on iOS instead of
/// defaulting to grey. [strokeWidth] applies to the Android arm only.
class AdaptiveProgressIndicator extends StatelessWidget {
  const AdaptiveProgressIndicator({
    super.key,
    this.size = 20,
    this.color,
    this.strokeWidth = 2,
  });

  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: context.isCupertino
          ? CupertinoActivityIndicator(radius: size / 2, color: color)
          : CircularProgressIndicator(strokeWidth: strokeWidth, color: color),
    );
  }
}
