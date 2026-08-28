import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/appointment_status_values.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_pill.dart';

// Re-exported so the widget layer keeps one import for the chip and its enum.
// The enum itself now lives in the Material-free domain owner, so the pure
// reducers (`dashboard_aggregator`, `schedule_snapshot`) no longer pull a
// widget file — and its Flutter import — into their graph.
export 'package:scheduling/features/calendar/domain/appointment_status_values.dart'
    show AppointmentStatus;

/// Localized status label.
String statusLabel(AppLocalizations l10n, AppointmentStatus status) =>
    switch (status) {
      AppointmentStatus.pending => l10n.status_pending,
      AppointmentStatus.inProgress => l10n.status_inProgress,
      AppointmentStatus.overdue => l10n.status_overdue,
      AppointmentStatus.done => l10n.status_done,
      AppointmentStatus.cancelled => l10n.status_cancelled,
    };

class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, super.key});
  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = _colorsFor(theme.statusColors);
    return StatusPill(
      label: statusLabel(context.l10n, status),
      background: bg,
      foreground: fg,
    );
  }

  (Color, Color) _colorsFor(AppStatusColors statusColors) => switch (status) {
    AppointmentStatus.pending => (
      // "Scheduled"
      statusColors.neutralContainer,
      statusColors.onNeutralContainer,
    ),
    AppointmentStatus.inProgress => (
      statusColors.inProgressContainer,
      statusColors.onInProgressContainer,
    ),
    AppointmentStatus.overdue => (
      statusColors.overdueContainer,
      statusColors.onOverdueContainer,
    ),
    AppointmentStatus.done => (
      statusColors.successContainer,
      statusColors.onSuccessContainer,
    ),
    AppointmentStatus.cancelled => (
      statusColors.neutralContainer,
      statusColors.onNeutralContainerMuted,
    ),
  };
}
