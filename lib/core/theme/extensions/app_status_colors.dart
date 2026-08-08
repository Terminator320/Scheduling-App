import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.invitedContainer,
    required this.onInvitedContainer,
    required this.inProgressContainer,
    required this.onInProgressContainer,
    required this.overdueContainer,
    required this.onOverdueContainer,
    required this.overdue,
    required this.accent,
    required this.neutralContainer,
    required this.onNeutralContainer,
    required this.onNeutralContainerMuted,
  });

  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color invitedContainer;
  final Color onInvitedContainer;
  final Color inProgressContainer;
  final Color onInProgressContainer;
  /// Standalone overdue accent, the sibling of [warning]/[success]/[accent].
  /// The dashboard bar needs a bar-fill hue, not a container tint.
  final Color overdue;
  final Color overdueContainer;
  final Color onOverdueContainer;
  final Color accent;
  final Color neutralContainer; // "Scheduled" + "Cancelled" chip fill
  final Color onNeutralContainer; // "Scheduled" chip text
  final Color onNeutralContainerMuted; // "Cancelled" chip text

  static const light = AppStatusColors(
    success: AppColors.green,
    successContainer: AppColors.greenFill,
    onSuccessContainer: AppColors.greenText,
    warning: AppColors.amber,
    warningContainer: AppColors.amberFill,
    onWarningContainer: AppColors.amberText,
    invitedContainer: AppColors.amberFill,
    onInvitedContainer: AppColors.amberText,
    inProgressContainer: AppColors.blueTint2,
    onInProgressContainer: AppColors.blue,
    overdueContainer: AppColors.redFill,
    onOverdueContainer: AppColors.redText,
    overdue: AppColors.orange,
    accent: AppColors.blue,
    neutralContainer: AppColors.paper,
    onNeutralContainer: AppColors.ink60,
    onNeutralContainerMuted: AppColors.ink25,
  );

  static const dark = AppStatusColors(
    success: AppColors.darkGreen,
    successContainer: Color(0x292BC48E),
    onSuccessContainer: AppColors.darkGreenText,
    warning: AppColors.darkAmber,
    warningContainer: Color(0x29F1A83C),
    onWarningContainer: AppColors.darkAmber,
    invitedContainer: Color(0x29F1A83C),
    onInvitedContainer: AppColors.darkAmber,
    inProgressContainer: Color(0x294B90F7),
    onInProgressContainer: AppColors.darkBlueOnTint,
    overdueContainer: Color(0x29FF6076),
    onOverdueContainer: AppColors.darkRedText,
    overdue: AppColors.darkOrange,
    accent: AppColors.darkBlueText,
    neutralContainer: Color(0x12FFFFFF),
    onNeutralContainer: AppColors.darkTextSecondary,
    onNeutralContainerMuted: AppColors.darkTextMuted,
  );

  @override
  AppStatusColors copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? invitedContainer,
    Color? onInvitedContainer,
    Color? inProgressContainer,
    Color? onInProgressContainer,
    Color? overdueContainer,
    Color? onOverdueContainer,
    Color? overdue,
    Color? accent,
    Color? neutralContainer,
    Color? onNeutralContainer,
    Color? onNeutralContainerMuted,
  }) {
    return AppStatusColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      invitedContainer: invitedContainer ?? this.invitedContainer,
      onInvitedContainer: onInvitedContainer ?? this.onInvitedContainer,
      inProgressContainer: inProgressContainer ?? this.inProgressContainer,
      onInProgressContainer:
          onInProgressContainer ?? this.onInProgressContainer,
      overdueContainer: overdueContainer ?? this.overdueContainer,
      onOverdueContainer: onOverdueContainer ?? this.onOverdueContainer,
      overdue: overdue ?? this.overdue,
      accent: accent ?? this.accent,
      neutralContainer: neutralContainer ?? this.neutralContainer,
      onNeutralContainer: onNeutralContainer ?? this.onNeutralContainer,
      onNeutralContainerMuted:
          onNeutralContainerMuted ?? this.onNeutralContainerMuted,
    );
  }

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    return AppStatusColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      invitedContainer: Color.lerp(
        invitedContainer,
        other.invitedContainer,
        t,
      )!,
      onInvitedContainer: Color.lerp(
        onInvitedContainer,
        other.onInvitedContainer,
        t,
      )!,
      inProgressContainer: Color.lerp(
        inProgressContainer,
        other.inProgressContainer,
        t,
      )!,
      onInProgressContainer: Color.lerp(
        onInProgressContainer,
        other.onInProgressContainer,
        t,
      )!,
      overdueContainer: Color.lerp(
        overdueContainer,
        other.overdueContainer,
        t,
      )!,
      onOverdueContainer: Color.lerp(
        onOverdueContainer,
        other.onOverdueContainer,
        t,
      )!,
      overdue: Color.lerp(overdue, other.overdue, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      neutralContainer: Color.lerp(
        neutralContainer,
        other.neutralContainer,
        t,
      )!,
      onNeutralContainer: Color.lerp(
        onNeutralContainer,
        other.onNeutralContainer,
        t,
      )!,
      onNeutralContainerMuted: Color.lerp(
        onNeutralContainerMuted,
        other.onNeutralContainerMuted,
        t,
      )!,
    );
  }
}

extension AppStatusColorsX on ThemeData {
  AppStatusColors get statusColors =>
      extension<AppStatusColors>() ??
      (brightness == Brightness.dark
          ? AppStatusColors.dark
          : AppStatusColors.light);
}
