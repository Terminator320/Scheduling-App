import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

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

  static const double _maxLabelScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColors = theme.statusColors;
    final (label, bg, fg) = _resolve(context.l10n, scheme, statusColors);
    final userScale = MediaQuery.textScalerOf(context).scale(1);
    final cappedScaler = TextScaler.linear(
      userScale < _maxLabelScale ? userScale : _maxLabelScale,
    );
    return Container(
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
    AppLocalizations l10n,
    ColorScheme scheme,
    AppStatusColors statusColors,
  ) => switch (status) {
    AppointmentStatus.confirmed => (
      l10n.status_confirmed,
      scheme.primaryContainer,
      scheme.onPrimaryContainer,
    ),
    AppointmentStatus.done => (
      l10n.status_done,
      statusColors.successContainer,
      statusColors.onSuccessContainer,
    ),
    AppointmentStatus.pending => (
      l10n.status_pending,
      statusColors.warningContainer,
      statusColors.onWarningContainer,
    ),
    AppointmentStatus.cancelled => (
      l10n.status_cancelled,
      scheme.errorContainer,
      scheme.onErrorContainer,
    ),
    AppointmentStatus.active => (
      l10n.status_active,
      statusColors.successContainer,
      statusColors.onSuccessContainer,
    ),
    AppointmentStatus.invited => (
      l10n.status_invited,
      statusColors.invitedContainer,
      statusColors.onInvitedContainer,
    ),
    AppointmentStatus.disabled => (
      l10n.status_disabled,
      scheme.surfaceContainerHighest,
      scheme.onSurfaceVariant,
    ),
    AppointmentStatus.inProgress => (
      l10n.status_inProgress,
      statusColors.inProgressContainer,
      statusColors.onInProgressContainer,
    ),
  };
}
