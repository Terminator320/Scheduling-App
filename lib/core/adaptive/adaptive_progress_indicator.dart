import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';

/// Platform-adaptive busy spinner — `CupertinoActivityIndicator` on iOS,
/// `CircularProgressIndicator` on Android. Honours [color] so in-button brand
/// spinners don't default to grey on iOS. [strokeWidth] only applies on Android.
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
