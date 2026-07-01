import 'package:flutter/material.dart';
import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';

/// Leading slot for a `*.icon` button: shows a small spinner while [isBusy],
/// otherwise [icon]. Consolidates the spinner-or-icon pattern repeated across
/// the detail views and action bars. The owning button keeps its own styling
/// and disables itself while busy — this widget only swaps the glyph.
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

  /// Spinner box size; defaults to [iconSize] when null.
  final double? spinnerSize;

  /// Applied to both the icon and the spinner; null uses the theme default.
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
