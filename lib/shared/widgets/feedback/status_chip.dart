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
  inProgress;

  /// Canonical mapping from a stored appointment status string.
  static AppointmentStatus fromRaw(String raw) => switch (raw.toLowerCase()) {
    'confirmed' => confirmed,
    'done' || 'completed' => done,
    'cancelled' => cancelled,
    'in_progress' || 'inprogress' => inProgress,
    _ => pending,
  };

  /// The pickable appointment statuses, in picker display order.
  static const appointmentValues = [
    confirmed,
    inProgress,
    pending,
    done,
    cancelled,
  ];

  /// The stored raw string for this status.
  String get raw => this == inProgress ? 'in_progress' : name;

  bool get isDone => this == done;
  bool get isCancelled => this == cancelled;

  /// Done/cancelled visits stay as records and exit the active workflow.
  bool get isTerminal => isDone || isCancelled;
}

/// Localized label for a status — shared by [StatusChip] and the
/// appointment status picker.
String statusLabel(AppLocalizations l10n, AppointmentStatus status) =>
    switch (status) {
      AppointmentStatus.confirmed => l10n.status_confirmed,
      AppointmentStatus.done => l10n.status_done,
      AppointmentStatus.pending => l10n.status_pending,
      AppointmentStatus.cancelled => l10n.status_cancelled,
      AppointmentStatus.active => l10n.status_active,
      AppointmentStatus.invited => l10n.status_invited,
      AppointmentStatus.disabled => l10n.status_disabled,
      AppointmentStatus.inProgress => l10n.status_inProgress,
    };

class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, super.key});
  final AppointmentStatus status;

  static const double _maxLabelScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColors = theme.statusColors;
    final label = statusLabel(context.l10n, status);
    final (bg, fg) = _colorsFor(scheme, statusColors);
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

  (Color, Color) _colorsFor(ColorScheme scheme, AppStatusColors statusColors) =>
      switch (status) {
        AppointmentStatus.confirmed => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
        AppointmentStatus.done => (
          statusColors.successContainer,
          statusColors.onSuccessContainer,
        ),
        AppointmentStatus.pending => (
          statusColors.warningContainer,
          statusColors.onWarningContainer,
        ),
        AppointmentStatus.cancelled => (
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
        AppointmentStatus.active => (
          statusColors.successContainer,
          statusColors.onSuccessContainer,
        ),
        AppointmentStatus.invited => (
          statusColors.invitedContainer,
          statusColors.onInvitedContainer,
        ),
        AppointmentStatus.disabled => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
        AppointmentStatus.inProgress => (
          statusColors.inProgressContainer,
          statusColors.onInProgressContainer,
        ),
      };
}
