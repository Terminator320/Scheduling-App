import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_pill.dart';

/// The appointment lifecycle: pending → in progress → done, plus a cancelled
/// terminal state reached by the separate Cancel action. User/account states
/// (active/invited/disabled) live in `UserStatus` — see `user_status_chip.dart`.
enum AppointmentStatus {
  pending,
  inProgress,
  done,
  cancelled;

  /// Canonical mapping from a stored appointment status string; any
  /// unrecognized value falls through to [pending].
  static AppointmentStatus fromRaw(String raw) => switch (raw.toLowerCase()) {
    'done' || 'completed' => done,
    'cancelled' => cancelled,
    'in_progress' || 'inprogress' => inProgress,
    _ => pending,
  };

  /// The pickable appointment statuses, in picker display order.
  static const appointmentValues = [pending, inProgress, done];

  /// The stored raw string for this status.
  String get raw => this == inProgress ? 'in_progress' : name;

  bool get isDone => this == done;
  bool get isCancelled => this == cancelled;

  /// Done/cancelled visits stay as records and exit the active workflow.
  bool get isTerminal => isDone || isCancelled;
}

/// Localized label for an appointment status — shared by [StatusChip] and the
/// appointment status picker.
String statusLabel(AppLocalizations l10n, AppointmentStatus status) =>
    switch (status) {
      AppointmentStatus.pending => l10n.status_pending,
      AppointmentStatus.inProgress => l10n.status_inProgress,
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
