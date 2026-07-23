import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_pill.dart';

/// Appointment states: pending → in_progress → done, plus cancelled; overdue is display-only.
enum AppointmentStatus {
  pending,
  inProgress,
  overdue,
  done,
  cancelled;

  /// Map stored status string to enum; unrecognized values default to pending.
  static AppointmentStatus fromRaw(String raw) => switch (raw.toLowerCase()) {
    'done' || 'completed' => done,
    'cancelled' => cancelled,
    'overdue' => overdue,
    'in_progress' || 'inprogress' => inProgress,
    _ => pending,
  };

  /// Pickable statuses (excludes display-only overdue).
  static const appointmentValues = [pending, inProgress, done];

  /// Normalize stored status to allowlist; legacy/unknown/overdue → pending.
  static String storedRaw(String raw) {
    final status = fromRaw(raw);
    return status == overdue ? pending.raw : status.raw;
  }

  /// Stored raw string; overdue throws to catch accidental writes early.
  String get raw => switch (this) {
    inProgress => 'in_progress',
    overdue => throw StateError(
      'overdue is display-only; it has no stored raw',
    ),
    _ => name,
  };

  bool get isDone => this == done;
  bool get isCancelled => this == cancelled;

  /// Terminal states exit the active workflow.
  bool get isTerminal => isDone || isCancelled;
}

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
    final (bg, fg) = _colorsFor(theme.colorScheme, theme.statusColors);
    return StatusPill(
      label: statusLabel(context.l10n, status),
      background: bg,
      foreground: fg,
    );
  }

  (Color, Color) _colorsFor(ColorScheme scheme, AppStatusColors statusColors) =>
      switch (status) {
        AppointmentStatus.pending => (
          statusColors.warningContainer,
          statusColors.onWarningContainer,
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
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      };
}
