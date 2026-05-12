import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary — cyan-blue matched to Plombier Eau Secours! logo (#1E82C8)
  static const Color primary = Color(0xFF1E82C8);
  static const Color primaryDark = Color(0xFF155E8E);
  static const Color primaryTint = Color(0xFFC5E6F6);
  static const Color primarySurface = Color(0xFFE8F5FC);

  // Light surfaces
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF1F5F9);
  static const Color onSurface = Color(0xFF0F172A);
  static const Color subtle = Color(0xFF64748B);
  static const Color muted = Color(0xFF94A3B8);
  static const Color outline = Color(0xFFE2E8F0);
  static const Color disabled = Color(0xFFCBD5E1);

  // Status — light
  static const Color success = Color(0xFF22C55E);
  static const Color successTint = Color(0xFFDCFCE7);
  static const Color successText = Color(0xFF166534);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningTint = Color(0xFFFEF9C3);
  static const Color warningText = Color(0xFF854D0E);
  static const Color error = Color(0xFFEF4444);
  static const Color errorTint = Color(0xFFFEF2F2);
  static const Color errorText = Color(0xFF991B1B);
  static const Color accent = Color(0xFF8B5CF6);

  // Dark surfaces
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkSurfaceAlt = Color(0xFF334155);
  static const Color darkOnSurface = Color(0xFFF1F5F9);
  static const Color darkSubtle = Color(0xFF64748B);
  static const Color darkMuted = Color(0xFF475569);
  // Was Color(0xFF1E293B) which matched darkSurface exactly, so dividers and
  // text-field borders were invisible against the dark surface.
  static const Color darkOutline = Color(0xFF475569);
  static const Color darkDisabled = Color(0xFF334155);

  // Status — dark
  static const Color darkPrimaryTint = Color(0xFF0C3A52);
  static const Color darkPrimaryOnDark = Color(0xFF93C5FD);
  static const Color darkSuccessTint = Color(0xFF14532D);
  static const Color darkSuccessText = Color(0xFF86EFAC);
  static const Color darkWarningTint = Color(0xFF422006);
  static const Color darkWarningText = Color(0xFFFCD34D);
  static const Color darkErrorTint = Color(0xFF450A0A);
  static const Color darkErrorText = Color(0xFFFCA5A5);
  static const Color darkAccent = Color(0xFFA78BFA);
  static const Color invitedTint = Color(0xFFF3E8FF);
  static const Color invitedText = Color(0xFF6B21A8);
  static const Color darkInvitedTint = Color(0xFF3B0764);
  static const Color darkInvitedText = Color(0xFFD8B4FE);

  // Employee color palette (used by AppAvatar auto-color + EmployeeColorGrid)
  static const List<Color> employeePalette = [
    Color(0xFF6366F1), // indigo
    Color(0xFFEC4899), // pink
    Color(0xFF10B981), // emerald
    Color(0xFFF59E0B), // amber
    Color(0xFF3B82F6), // blue
    Color(0xFF8B5CF6), // violet
    Color(0xFFEF4444), // red
    Color(0xFF14B8A6), // teal
    Color(0xFFF97316), // orange
    Color(0xFF06B6D4), // cyan
  ];
}

class AppSpacing {
  AppSpacing._();
  static const double sp4 = 4;
  static const double sp8 = 8;
  static const double sp12 = 12;
  static const double sp16 = 16;
  static const double sp24 = 24;
  static const double sp32 = 32;
}

class AppRadius {
  AppRadius._();
  static const double r4 = 4;
  static const double r8 = 8;
  static const double r12 = 12;
  static const double r16 = 16;
  static const double rFull = 999;
}

class AppShadow {
  AppShadow._();
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> sheet = [
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, -4)),
  ];
}

class AppDuration {
  AppDuration._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration shimmer = Duration(milliseconds: 1200);
}

/// Status hues with no clean Material 3 ColorScheme analog (invited = purple,
/// inProgress = sky blue). Exposed via `Theme.of(context).extension<AppStatusColors>()`
/// so widget `build()` methods stay free of static `AppColors.*` references.
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
    required this.accent,
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
  final Color accent;

  static const light = AppStatusColors(
    success: AppColors.success,
    successContainer: AppColors.successTint,
    onSuccessContainer: AppColors.successText,
    warning: AppColors.warning,
    warningContainer: AppColors.warningTint,
    onWarningContainer: AppColors.warningText,
    invitedContainer: AppColors.invitedTint,
    onInvitedContainer: AppColors.invitedText,
    inProgressContainer: Color(0xFFE0F2FE),
    onInProgressContainer: Color(0xFF0369A1),
    accent: AppColors.accent,
  );

  static const dark = AppStatusColors(
    success: AppColors.success,
    successContainer: AppColors.darkSuccessTint,
    onSuccessContainer: AppColors.darkSuccessText,
    warning: AppColors.warning,
    warningContainer: AppColors.darkWarningTint,
    onWarningContainer: AppColors.darkWarningText,
    invitedContainer: AppColors.darkInvitedTint,
    onInvitedContainer: AppColors.darkInvitedText,
    inProgressContainer: Color(0xFF0C4A6E),
    onInProgressContainer: Color(0xFF7DD3FC),
    accent: AppColors.darkAccent,
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
    Color? accent,
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
      accent: accent ?? this.accent,
    );
  }

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    return AppStatusColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      invitedContainer:
          Color.lerp(invitedContainer, other.invitedContainer, t)!,
      onInvitedContainer:
          Color.lerp(onInvitedContainer, other.onInvitedContainer, t)!,
      inProgressContainer:
          Color.lerp(inProgressContainer, other.inProgressContainer, t)!,
      onInProgressContainer:
          Color.lerp(onInProgressContainer, other.onInProgressContainer, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}

extension AppStatusColorsX on ThemeData {
  AppStatusColors get statusColors =>
      extension<AppStatusColors>() ??
      (brightness == Brightness.dark ? AppStatusColors.dark : AppStatusColors.light);
}
