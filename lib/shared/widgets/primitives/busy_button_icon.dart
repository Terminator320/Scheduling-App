import 'package:flutter/material.dart';
import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';

/// Leading slot for icon buttons. Swaps to a spinner while busy.
class BusyButtonIcon extends StatelessWidget {
  const BusyButtonIcon({
    required this.isBusy,
    required this.icon,
    super.key,
    this.iconSize = 18,
    this.spinnerSize,
    this.color,
  });

  final bool isBusy;
  final IconData icon;
  final double iconSize;

  /// Spinner size; defaults to iconSize when null.
  final double? spinnerSize;

  /// Color for icon and spinner.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (!isBusy) return Icon(icon, size: iconSize, color: color);
    return AdaptiveProgressIndicator(
      size: spinnerSize ?? iconSize,
      color: color,
    );
  }
}
