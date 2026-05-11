// lib/shared/widgets/status_chip.dart
import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

enum AppointmentStatus { confirmed, done, pending, cancelled, invited, active, disabled, inProgress }

class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, super.key});
  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (label, bg, fg) = _resolve(isDark);
    return Container(
      // 10px horizontal: sp8 (8) + 2px optical correction for pill label
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp8 + 2, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  (String, Color, Color) _resolve(bool isDark) => switch (status) {
    AppointmentStatus.confirmed => (
      'Confirmed',
      isDark ? AppColors.darkPrimaryTint : AppColors.primaryTint,
      isDark ? AppColors.darkPrimaryOnDark : AppColors.primaryDark,
    ),
    AppointmentStatus.done => (
      'Done',
      isDark ? AppColors.darkSuccessTint : AppColors.successTint,
      isDark ? AppColors.darkSuccessText : AppColors.successText,
    ),
    AppointmentStatus.pending => (
      'Pending',
      isDark ? AppColors.darkWarningTint : AppColors.warningTint,
      isDark ? AppColors.darkWarningText : AppColors.warningText,
    ),
    AppointmentStatus.cancelled => (
      'Cancelled',
      isDark ? AppColors.darkErrorTint : AppColors.errorTint,
      isDark ? AppColors.darkErrorText : AppColors.errorText,
    ),
    AppointmentStatus.active => (
      'Active',
      isDark ? AppColors.darkSuccessTint : AppColors.successTint,
      isDark ? AppColors.darkSuccessText : AppColors.successText,
    ),
    AppointmentStatus.invited => (
      'Invited',
      isDark ? AppColors.darkInvitedTint : AppColors.invitedTint,
      isDark ? AppColors.darkInvitedText : AppColors.invitedText,
    ),
    AppointmentStatus.disabled => (
      'Disabled',
      isDark ? AppColors.darkDisabled : AppColors.disabled,
      isDark ? AppColors.darkMuted : AppColors.subtle,
    ),
    AppointmentStatus.inProgress => (
      'In Progress',
      isDark ? const Color(0xFF0C4A6E) : const Color(0xFFE0F2FE),
      isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0369A1),
    ),
  };
}
