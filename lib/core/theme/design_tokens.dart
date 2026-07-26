import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF005CC8); // Royal Blue
  static const Color primaryDark = Color(0xFF00256B); // Dark Navy Blue
  static const Color primaryTint = Color(0xFF7FD3FF); // Light Sky Blue
  static const Color primarySurface = Color(0xFFE6F4FF);

  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF1F5F9);
  static const Color onSurface = Color(
    0xFF00256B,
  ); // Dark Navy Blue (main text)
  static const Color subtle = Color(0xFF5A6B8C);
  static const Color muted = Color(0xFF8A99B5);
  static const Color outline = Color(0xFFD8E1EF);

  static const Color success = Color(0xFF22C55E);
  static const Color successTint = Color(0xFFDCFCE7);
  static const Color successText = Color(0xFF166534);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningTint = Color(0xFFFEF9C3);
  static const Color warningText = Color(0xFF854D0E);
  static const Color error = Color(0xFFD61F3A); // Plunger Red
  static const Color errorTint = Color(0xFFFDE7EA);
  static const Color errorText = Color(0xFF7A1124);
  static const Color accent = Color(0xFF00A6F4); // Bright Blue

  static const Color darkBackground = Color(0xFF0A1633); // Dark Outline
  static const Color darkSurface = Color(0xFF142347);
  static const Color darkSurfaceAlt = Color(0xFF1E3260);
  static const Color darkOnSurface = Color(0xFFE6F0FF);
  static const Color darkSubtle = Color(0xFF8FA3C7);
  static const Color darkMuted = Color(0xFF5A6B8C);
  static const Color darkOutline = Color(0xFF2A3B66);

  static const Color darkPrimaryTint = Color(0xFF07214F);
  static const Color darkPrimaryOnDark = Color(0xFF7FD3FF); // Light Sky Blue
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
  static const double r8 = 8;
  static const double r12 = 12;
  static const double r16 = 16;
  static const double r20 = 20;
  static const double r24 = 24;
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

  /// Tight lift under a small selected control (segmented pill).
  static const List<BoxShadow> pill = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 3, offset: Offset(0, 1)),
  ];
}

class AppDuration {
  AppDuration._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration shimmer = Duration(milliseconds: 1200);
}

class AppMotion {
  AppMotion._();

  /// Shared open/close curve for `showModalBottomSheet` across the app.
  static const AnimationStyle sheetStyle = AnimationStyle(
    duration: Duration(milliseconds: 280),
    reverseDuration: Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
  );

  /// Cross-fade duration when switching hub tabs (persistent shell fades between mounted tabs).
  static const Duration tabSwitch = Duration(milliseconds: 220);
}

/// Picks black or white, whichever contrasts with [background]. This is
/// data-driven off the actual color, not the theme's brightness setting.
Color contrastingForegroundFor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
    ? Colors.white
    : Colors.black;

/// Surface-card decoration shared across settings. Light/dark treatment
/// comes from [AppCardStyle].
BoxDecoration appCardDecoration(
  ThemeData theme, {
  double radius = AppRadius.r12,
  Color? color,
}) {
  final style = theme.cardStyle;
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: style.shadow,
    border: style.border,
  );
}

/// Per-theme surface-card treatment (shadow vs. border), registered on
/// ThemeData.extensions so it can be looked up without checking brightness directly.
@immutable
class AppCardStyle extends ThemeExtension<AppCardStyle> {
  const AppCardStyle({
    required this.shadow,
    required this.border,
    required this.iconChipAlpha,
  });

  final List<BoxShadow>? shadow;
  final BoxBorder? border;

  /// Background alpha for tinted icon chips (e.g. drawer nav items).
  final double iconChipAlpha;

  static const light = AppCardStyle(
    shadow: AppShadow.card,
    border: null,
    iconChipAlpha: 0.10,
  );

  static const dark = AppCardStyle(
    shadow: null,
    border: Border.fromBorderSide(BorderSide(color: AppColors.darkSurfaceAlt)),
    iconChipAlpha: 0.15,
  );

  @override
  AppCardStyle copyWith({
    List<BoxShadow>? shadow,
    BoxBorder? border,
    double? iconChipAlpha,
  }) {
    return AppCardStyle(
      shadow: shadow ?? this.shadow,
      border: border ?? this.border,
      iconChipAlpha: iconChipAlpha ?? this.iconChipAlpha,
    );
  }

  @override
  AppCardStyle lerp(ThemeExtension<AppCardStyle>? other, double t) {
    if (other is! AppCardStyle) return this;
    return AppCardStyle(
      shadow: BoxShadow.lerpList(shadow, other.shadow, t),
      border: BoxBorder.lerp(border, other.border, t),
      iconChipAlpha:
          lerpDouble(iconChipAlpha, other.iconChipAlpha, t) ?? iconChipAlpha,
    );
  }
}

extension AppCardStyleX on ThemeData {
  AppCardStyle get cardStyle =>
      extension<AppCardStyle>() ??
      (brightness == Brightness.dark ? AppCardStyle.dark : AppCardStyle.light);
}

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
  final Color overdueContainer;
  final Color onOverdueContainer;
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
    overdueContainer: Color(0xFFFFEDD5),
    onOverdueContainer: Color(0xFFC2410C),
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
    overdueContainer: Color(0xFF7C2D12),
    onOverdueContainer: Color(0xFFFDBA74),
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
    Color? overdueContainer,
    Color? onOverdueContainer,
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
      overdueContainer: overdueContainer ?? this.overdueContainer,
      onOverdueContainer: onOverdueContainer ?? this.onOverdueContainer,
      accent: accent ?? this.accent,
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
      accent: Color.lerp(accent, other.accent, t)!,
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
