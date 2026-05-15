// lib/shared/widgets/status_chip.dart
import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

enum AppointmentStatus {
  confirmed,
  done,
  pending,
  cancelled,
  invited,
  active,
  disabled,
  inProgress,
}

class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, super.key});
  final AppointmentStatus status;

  // Soft cap on text scaling for the chip label. The pill design depends on
  // a compact width to sit next to titles and icons; at 2× scale the chip
  // crowds the row and breaks layouts. 1.3× still helps low-vision users
  // without blowing up the chip. This is the documented "visual reason" the
  // frontend rule allows.
  static const double _maxLabelScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColors = theme.statusColors;
    final (label, bg, fg) = _resolve(scheme, statusColors);
    final userScale = MediaQuery.textScalerOf(context).scale(1);
    final cappedScaler = TextScaler.linear(
      userScale < _maxLabelScale ? userScale : _maxLabelScale,
    );
    return Container(
      // 10px horizontal: sp8 (8) + 2px optical correction for pill label
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp8 + 2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
      child: Text(
        label,
        textScaler: cappedScaler,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  (String, Color, Color) _resolve(
    ColorScheme scheme,
    AppStatusColors statusColors,
  ) => switch (status) {
    AppointmentStatus.confirmed => (
      'Confirmed',
      scheme.primaryContainer,
      scheme.onPrimaryContainer,
    ),
    AppointmentStatus.done => (
      'Done',
      statusColors.successContainer,
      statusColors.onSuccessContainer,
    ),
    AppointmentStatus.pending => (
      'Pending',
      statusColors.warningContainer,
      statusColors.onWarningContainer,
    ),
    AppointmentStatus.cancelled => (
      'Cancelled',
      scheme.errorContainer,
      scheme.onErrorContainer,
    ),
    AppointmentStatus.active => (
      'Active',
      statusColors.successContainer,
      statusColors.onSuccessContainer,
    ),
    AppointmentStatus.invited => (
      'Invited',
      statusColors.invitedContainer,
      statusColors.onInvitedContainer,
    ),
    AppointmentStatus.disabled => (
      'Disabled',
      scheme.surfaceContainerHighest,
      scheme.onSurfaceVariant,
    ),
    AppointmentStatus.inProgress => (
      'In Progress',
      statusColors.inProgressContainer,
      statusColors.onInProgressContainer,
    ),
  };
}
