import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Sans family for all UI text. Bundled as a static-instance asset family.
const String kFontSans = 'InstrumentSans';

/// Mono family for numbers, times, counts and all-caps section labels.
/// Reached through [AppMonoType], never by hand at a call site.
const String kFontMono = 'IBMPlexMono';

class AppColors {
  AppColors._();

  static const Color surface = Color(0xFFFFFFFF);

  // --- Redesign vocabulary (2026-07-30). Light roles. ---
  static const Color ink = Color(0xFF0B1A33);
  static const Color ink80 = Color(0xFF3E4C63);
  static const Color ink60 = Color(0xFF5A6B85);
  static const Color ink40 = Color(0xFF8A99B0);
  static const Color ink25 = Color(0xFFA6B2C4);
  static const Color ink15 = Color(0xFFC0CAD8);
  static const Color hairline = Color(0xFFDCE3EC);
  static const Color border = Color(0xFFE4E9F1);
  static const Color track = Color(0xFFEEF1F6);
  static const Color paper = Color(0xFFF1F4F9);
  static const Color paper2 = Color(0xFFE7ECF3);
  static const Color sheet = Color(0xFFF5F7FB);
  static const Color lockedPanel = Color(0xFFF7F9FC);
  static const Color surfaceHover = Color(0xFFFBFCFE);
  static const Color blue = Color(0xFF005CC8);
  static const Color navy = Color(0xFF00256B);
  static const Color blueTint = Color(0xFFEFF4FC);
  static const Color blueTintHover = Color(0xFFE2ECFA);
  static const Color blueTint2 = Color(0xFFE4F0FF);
  static const Color green = Color(0xFF0E9B6E);
  static const Color greenText = Color(0xFF0B7A57);
  static const Color greenFill = Color(0xFFE6F5EF);
  static const Color amber = Color(0xFFE08A00);
  static const Color amberText = Color(0xFF8A5C00);
  static const Color amberFill = Color(0xFFFFF4E5);
  static const Color red = Color(0xFFD61F3A);
  /// Overdue sits between amber and red on purpose — it is "late", not
  /// "failed", and `error` red already means cancelled on the same chart.
  static const Color orange = Color(0xFFF54A00);
  static const Color redText = Color(0xFFB01730);
  static const Color redFill = Color(0xFFFDE8EC);

  // --- Redesign vocabulary. Dark roles. ---
  static const Color darkPage = Color(0xFF0C1220);
  static const Color darkCard = Color(0xFF151E2E);
  static const Color darkSheet = Color(0xFF101827);
  static const Color darkSheetRow = Color(0xFF18212F);
  static const Color darkNotice = Color(0xFF1A2436);
  static const Color darkTextPrimary = Color(0xFFEEF2F8);
  static const Color darkTextSecondary = Color(0xFFB3C0D4);
  static const Color darkTextTertiary = Color(0xFF8593A9);
  static const Color darkTextMuted = Color(0xFF5C6A80);
  static const Color darkBlueText = Color(0xFF4B90F7);
  static const Color darkBlueFill = Color(0xFF1D6BE8);
  static const Color darkBlueOnTint = Color(0xFF7FB2FA);
  static const Color darkNavy = Color(0xFF1D4ED8);
  static const Color darkGreen = Color(0xFF1FA97A);
  static const Color darkGreenText = Color(0xFF4FD8A6);
  static const Color darkAmber = Color(0xFFF1A83C);
  static const Color darkRed = Color(0xFFFF6076);
  static const Color darkRedText = Color(0xFFFF8A99);
  static const Color darkOrange = Color(0xFFFF8A4C);

  /// The ten assignable crew colours — the app's primary data encoding
  /// (card bar, avatar, calendar dot, map pin, workload bar, route rail).
  /// STORED in Firestore as the light-theme ARGB int; dark rendering
  /// resolves through [crewColorOf], never by re-storing a lifted value.
  static const List<Color> crewPalette = [
    Color(0xFF005CC8), // blue
    Color(0xFF7A3FF2), // violet
    Color(0xFF0E9B6E), // green
    Color(0xFFE08A00), // amber
    Color(0xFF00A5C4), // cyan
    Color(0xFFC43F8E), // magenta
    Color(0xFFD61F3A), // red
    Color(0xFF5A6B85), // slate
    Color(0xFF8A5A2B), // brown
    Color(0xFF7A8F1F), // olive
  ];
}

/// Stored (light) crew ARGB -> the colour the dark theme renders instead.
/// Lifted ~15% in lightness per `09-dark-theme.md`.
const Map<int, Color> _darkCrewOverride = {
  0xFF005CC8: Color(0xFF4B90F7),
  0xFF7A3FF2: Color(0xFF9B6BFF),
  0xFF0E9B6E: Color(0xFF2BC48E),
  0xFFE08A00: Color(0xFFF1A83C),
  0xFF00A5C4: Color(0xFF35C2DE),
  0xFFC43F8E: Color(0xFFE45FA8),
  0xFFD61F3A: Color(0xFFFF6076),
  0xFF5A6B85: Color(0xFF8593A9),
  0xFF8A5A2B: Color(0xFFC9985A),
  0xFF7A8F1F: Color(0xFFB9CC45),
};

/// Resolves a STORED employee colour int to the colour this theme renders.
/// Canonical hues hit the exact per-theme map; anything custom-picked (or
/// left over from the pre-redesign palette) gets a generic HSL lift whose
/// amount is theme data — 0 in light, so light is exact identity.
Color crewColorOf(ThemeData theme, int storedArgb) {
  final palette = theme.palette;
  final mapped = palette.crewOverride[storedArgb];
  if (mapped != null) return mapped;
  if (palette.crewCustomLift == 0) return Color(storedArgb);
  final hsl = HSLColor.fromColor(Color(storedArgb));
  return hsl
      .withLightness((hsl.lightness + palette.crewCustomLift).clamp(0.0, 0.92))
      .withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0))
      .toColor();
}

/// Foreground for text/icons sitting on a crew-coloured surface (avatars,
/// map pins). Light: plain contrast. Dark: a near-black tint of the
/// surface's OWN hue — white on a lifted crew colour fails contrast at
/// avatar sizes (`09-dark-theme.md` rule 2).
Color avatarForegroundFor(ThemeData theme, Color background) {
  final inkLightness = theme.palette.avatarInkLightness;
  if (inkLightness == null) return contrastingForegroundFor(background);
  final hsl = HSLColor.fromColor(background);
  return hsl
      .withSaturation((hsl.saturation * 0.7).clamp(0.0, 1.0))
      .withLightness(inkLightness)
      .toColor();
}

class AppSpacing {
  AppSpacing._();
  static const double sp4 = 4;
  static const double sp8 = 8;
  static const double sp12 = 12;
  static const double sp16 = 16;
  static const double sp24 = 24;
  static const double sp32 = 32;

  static const double cardPaddingY = 12;
}

class AppRadius {
  AppRadius._();
  static const double r8 = 8;
  static const double r12 = 12;
  static const double r16 = 16;
  static const double r20 = 20;
  static const double r24 = 24;
  static const double rFull = 999;

  static const double rCard = 15;
  static const double rPanel = 18;
  static const double rSheet = 26;
  static const double rDialog = 22;
  static const double rFab = 20;
  static const double rIcon = 12;
  static const double rThumb = 9;
  static const double rRow = 13;
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
    duration: Duration(milliseconds: 300),
    reverseDuration: Duration(milliseconds: 240),
    curve: Cubic(0.2, 0.9, 0.25, 1),
  );

  /// Cross-fade duration when switching hub tabs (persistent shell fades between mounted tabs).
  static const Duration tabSwitch = Duration(milliseconds: 220);

  static const Curve emphasized = Cubic(0.2, 0.9, 0.25, 1);
  static const Duration popIn = Duration(milliseconds: 200);
  static const Duration drawer = Duration(milliseconds: 260);
  static const Duration riseInShort = Duration(milliseconds: 240);

  /// Total in-hold-out lifetime of a notice (`06-sheets-and-dialogs.md` §11).
  static const Duration noticeCycle = Duration(milliseconds: 2600);
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
    required this.sheetShadow,
    required this.drawerShadow,
    required this.noticeShadow,
    required this.pillShadow,
  });

  final List<BoxShadow>? shadow;
  final BoxBorder? border;

  /// Background alpha for tinted icon chips (e.g. drawer nav items).
  final double iconChipAlpha;

  final List<BoxShadow> sheetShadow;
  final List<BoxShadow> drawerShadow;
  final List<BoxShadow> noticeShadow;
  final List<BoxShadow> pillShadow;

  static const light = AppCardStyle(
    shadow: [
      BoxShadow(color: Color(0x0D0B1A33), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(
        color: Color(0x4D0B1A33),
        blurRadius: 24,
        spreadRadius: -16,
        offset: Offset(0, 10),
      ),
    ],
    border: null,
    iconChipAlpha: 0.10,
    sheetShadow: [
      BoxShadow(
        color: Color(0x660B1A33),
        blurRadius: 30,
        spreadRadius: -12,
        offset: Offset(0, 12),
      ),
    ],
    drawerShadow: [
      BoxShadow(
        color: Color(0x660B1A33),
        blurRadius: 44,
        spreadRadius: -18,
        offset: Offset(-18, 0),
      ),
    ],
    noticeShadow: [
      BoxShadow(
        color: Color(0x990B1A33),
        blurRadius: 32,
        spreadRadius: -12,
        offset: Offset(0, 14),
      ),
    ],
    pillShadow: [
      BoxShadow(
        color: Color(0x660B1A33),
        blurRadius: 16,
        spreadRadius: -6,
        offset: Offset(0, 6),
      ),
    ],
  );

  static const dark = AppCardStyle(
    // Dark separates by surface stepping, not shadow — this is edge
    // definition only (`09-dark-theme.md` rule 1).
    shadow: [
      BoxShadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1)),
    ],
    border: Border.fromBorderSide(BorderSide(color: Color(0x12FFFFFF))),
    iconChipAlpha: 0.15,
    sheetShadow: [
      BoxShadow(
        color: Color(0xCC000000),
        blurRadius: 30,
        spreadRadius: -12,
        offset: Offset(0, 12),
      ),
    ],
    drawerShadow: [
      BoxShadow(
        color: Color(0xCC000000),
        blurRadius: 44,
        spreadRadius: -18,
        offset: Offset(-18, 0),
      ),
    ],
    noticeShadow: [
      BoxShadow(
        color: Color(0xCC000000),
        blurRadius: 32,
        spreadRadius: -12,
        offset: Offset(0, 14),
      ),
    ],
    pillShadow: [
      BoxShadow(
        color: Color(0xCC000000),
        blurRadius: 16,
        spreadRadius: -6,
        offset: Offset(0, 6),
      ),
    ],
  );

  @override
  AppCardStyle copyWith({
    List<BoxShadow>? shadow,
    BoxBorder? border,
    double? iconChipAlpha,
    List<BoxShadow>? sheetShadow,
    List<BoxShadow>? drawerShadow,
    List<BoxShadow>? noticeShadow,
    List<BoxShadow>? pillShadow,
  }) {
    return AppCardStyle(
      shadow: shadow ?? this.shadow,
      border: border ?? this.border,
      iconChipAlpha: iconChipAlpha ?? this.iconChipAlpha,
      sheetShadow: sheetShadow ?? this.sheetShadow,
      drawerShadow: drawerShadow ?? this.drawerShadow,
      noticeShadow: noticeShadow ?? this.noticeShadow,
      pillShadow: pillShadow ?? this.pillShadow,
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
      sheetShadow:
          BoxShadow.lerpList(sheetShadow, other.sheetShadow, t) ?? sheetShadow,
      drawerShadow:
          BoxShadow.lerpList(drawerShadow, other.drawerShadow, t) ??
          drawerShadow,
      noticeShadow:
          BoxShadow.lerpList(noticeShadow, other.noticeShadow, t) ??
          noticeShadow,
      pillShadow:
          BoxShadow.lerpList(pillShadow, other.pillShadow, t) ?? pillShadow,
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

/// Every design role Material's ColorScheme has no slot for.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.textBody,
    required this.textTertiary,
    required this.textMuted,
    required this.textFaint,
    required this.decorFaint,
    required this.primaryAccent,
    required this.blueTintPressed,
    required this.sheetRow,
    required this.lockedPanel,
    required this.lockedPanelBorder,
    required this.track,
    required this.dangerFill,
    required this.onDangerFill,
    required this.noticeMint,
    required this.noticeInfo,
    required this.noticeRed,
    required this.heroGradient,
    required this.crewOverride,
    required this.crewCustomLift,
    required this.avatarInkLightness,
  });

  final Color textBody; // body copy — Ink 80
  final Color textTertiary; // labels — Ink 40
  final Color textMuted; // captions, inactive — Ink 25
  final Color textFaint; // chevrons, placeholder — Ink 15
  final Color decorFaint; // grabber, decorative strokes
  final Color primaryAccent; // blue for TEXT and ICONS (lifted in dark)
  final Color blueTintPressed; // pressed state on tinted icon buttons
  final Color sheetRow; // row card inside a sheet
  final Color lockedPanel; // read-only field group
  final Color lockedPanelBorder;
  final Color track; // progress-bar tracks
  final Color dangerFill; // saturated destructive button fill
  final Color onDangerFill;
  final Color noticeMint; // toast dots — the toast surface is dark in
  final Color noticeInfo; // BOTH themes, so these four are identical
  final Color noticeRed;
  final Gradient heroGradient;
  final Map<int, Color> crewOverride;
  final double crewCustomLift;
  final double? avatarInkLightness; // null = plain contrast foreground

  static const light = AppPalette(
    textBody: AppColors.ink80,
    textTertiary: AppColors.ink40,
    textMuted: AppColors.ink25,
    textFaint: AppColors.ink15,
    decorFaint: AppColors.ink15,
    primaryAccent: AppColors.blue,
    blueTintPressed: AppColors.blueTintHover,
    sheetRow: Color(0xFFFFFFFF),
    lockedPanel: AppColors.lockedPanel,
    lockedPanelBorder: Color(0x120B1A33),
    track: AppColors.track,
    dangerFill: AppColors.red,
    onDangerFill: Color(0xFFFFFFFF),
    noticeMint: Color(0xFF7FE3C0),
    noticeInfo: Color(0xFF7FCBFF),
    noticeRed: Color(0xFFFF9AA8),
    heroGradient: LinearGradient(
      begin: Alignment(-0.5, -1),
      end: Alignment(0.5, 1),
      colors: [AppColors.blue, AppColors.navy],
    ),
    crewOverride: {},
    crewCustomLift: 0,
    avatarInkLightness: null,
  );

  static const dark = AppPalette(
    textBody: Color(0xFFC5D0E2),
    textTertiary: AppColors.darkTextTertiary,
    textMuted: AppColors.darkTextMuted,
    textFaint: Color(0xFF3A465A),
    decorFaint: Color(0xFF2C3648),
    primaryAccent: AppColors.darkBlueText,
    blueTintPressed: Color(0x334B90F7),
    sheetRow: AppColors.darkSheetRow,
    lockedPanel: Color(0xFF121B2A),
    lockedPanelBorder: Color(0x12FFFFFF),
    track: Color(0x14FFFFFF),
    dangerFill: AppColors.red,
    onDangerFill: Color(0xFFFFFFFF),
    noticeMint: Color(0xFF7FE3C0),
    noticeInfo: Color(0xFF7FCBFF),
    noticeRed: Color(0xFFFF9AA8),
    heroGradient: LinearGradient(
      begin: Alignment(-0.5, -1),
      end: Alignment(0.5, 1),
      colors: [AppColors.darkBlueFill, AppColors.darkNavy],
    ),
    crewOverride: _darkCrewOverride,
    crewCustomLift: 0.18,
    avatarInkLightness: 0.07,
  );

  @override
  AppPalette copyWith({
    Color? textBody,
    Color? textTertiary,
    Color? textMuted,
    Color? textFaint,
    Color? decorFaint,
    Color? primaryAccent,
    Color? blueTintPressed,
    Color? sheetRow,
    Color? lockedPanel,
    Color? lockedPanelBorder,
    Color? track,
    Color? dangerFill,
    Color? onDangerFill,
    Color? noticeMint,
    Color? noticeInfo,
    Color? noticeRed,
    Gradient? heroGradient,
    Map<int, Color>? crewOverride,
    double? crewCustomLift,
    double? avatarInkLightness,
  }) => AppPalette(
    textBody: textBody ?? this.textBody,
    textTertiary: textTertiary ?? this.textTertiary,
    textMuted: textMuted ?? this.textMuted,
    textFaint: textFaint ?? this.textFaint,
    decorFaint: decorFaint ?? this.decorFaint,
    primaryAccent: primaryAccent ?? this.primaryAccent,
    blueTintPressed: blueTintPressed ?? this.blueTintPressed,
    sheetRow: sheetRow ?? this.sheetRow,
    lockedPanel: lockedPanel ?? this.lockedPanel,
    lockedPanelBorder: lockedPanelBorder ?? this.lockedPanelBorder,
    track: track ?? this.track,
    dangerFill: dangerFill ?? this.dangerFill,
    onDangerFill: onDangerFill ?? this.onDangerFill,
    noticeMint: noticeMint ?? this.noticeMint,
    noticeInfo: noticeInfo ?? this.noticeInfo,
    noticeRed: noticeRed ?? this.noticeRed,
    heroGradient: heroGradient ?? this.heroGradient,
    crewOverride: crewOverride ?? this.crewOverride,
    crewCustomLift: crewCustomLift ?? this.crewCustomLift,
    avatarInkLightness: avatarInkLightness ?? this.avatarInkLightness,
  );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      textBody: Color.lerp(textBody, other.textBody, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      decorFaint: Color.lerp(decorFaint, other.decorFaint, t)!,
      primaryAccent: Color.lerp(primaryAccent, other.primaryAccent, t)!,
      blueTintPressed: Color.lerp(blueTintPressed, other.blueTintPressed, t)!,
      sheetRow: Color.lerp(sheetRow, other.sheetRow, t)!,
      lockedPanel: Color.lerp(lockedPanel, other.lockedPanel, t)!,
      lockedPanelBorder: Color.lerp(
        lockedPanelBorder,
        other.lockedPanelBorder,
        t,
      )!,
      track: Color.lerp(track, other.track, t)!,
      dangerFill: Color.lerp(dangerFill, other.dangerFill, t)!,
      onDangerFill: Color.lerp(onDangerFill, other.onDangerFill, t)!,
      noticeMint: Color.lerp(noticeMint, other.noticeMint, t)!,
      noticeInfo: Color.lerp(noticeInfo, other.noticeInfo, t)!,
      noticeRed: Color.lerp(noticeRed, other.noticeRed, t)!,
      heroGradient: Gradient.lerp(heroGradient, other.heroGradient, t)!,
      // Discrete data, not colours — snap at the midpoint.
      crewOverride: t < 0.5 ? crewOverride : other.crewOverride,
      crewCustomLift:
          lerpDouble(crewCustomLift, other.crewCustomLift, t) ?? crewCustomLift,
      avatarInkLightness: t < 0.5
          ? avatarInkLightness
          : other.avatarInkLightness,
    );
  }
}

extension AppPaletteX on ThemeData {
  AppPalette get palette =>
      extension<AppPalette>() ??
      (brightness == Brightness.dark ? AppPalette.dark : AppPalette.light);
}

/// Named mono styles for numbers, times, counts and all-caps labels.
/// A call site writes `theme.monoType.data` — never a raw fontFamily.
@immutable
class AppMonoType extends ThemeExtension<AppMonoType> {
  const AppMonoType({
    required this.data,
    required this.metric,
    required this.label,
    required this.groupLabel,
    required this.fieldLabel,
    required this.micro,
    required this.numeralHero,
    required this.numeralKpi,
    required this.numeralSection,
    required this.numeralSub,
  });

  /// Builds one themed set. Sizes and tracking are theme-invariant — only the
  /// three colours move between light and dark. Deliberately not `const`: a
  /// const initializer may not construct an object from a parameter, so the
  /// alternative is duplicating all ten styles per theme.
  AppMonoType._of({
    required Color ink,
    required Color secondary,
    required Color tertiary,
  }) : data = TextStyle(
         fontFamily: kFontMono,
         fontSize: 12.5,
         height: 1,
         fontWeight: FontWeight.w500,
         color: secondary,
       ),
       metric = TextStyle(
         fontFamily: kFontMono,
         fontSize: 15,
         height: 1,
         fontWeight: FontWeight.w600,
         color: ink,
       ),
       label = TextStyle(
         fontFamily: kFontMono,
         fontSize: 11,
         height: 1,
         fontWeight: FontWeight.w600,
         letterSpacing: 1.1,
         color: tertiary,
       ),
       groupLabel = TextStyle(
         fontFamily: kFontMono,
         fontSize: 10.5,
         height: 1,
         fontWeight: FontWeight.w600,
         letterSpacing: 1.16,
         color: tertiary,
       ),
       fieldLabel = TextStyle(
         fontFamily: kFontMono,
         fontSize: 10,
         height: 1,
         fontWeight: FontWeight.w600,
         letterSpacing: 0.9,
         color: tertiary,
       ),
       micro = TextStyle(
         fontFamily: kFontMono,
         fontSize: 9.5,
         height: 1,
         fontWeight: FontWeight.w500,
         letterSpacing: 0.57,
         color: tertiary,
       ),
       numeralHero = TextStyle(
         fontFamily: kFontMono,
         fontSize: 44,
         height: 1,
         fontWeight: FontWeight.w700,
         letterSpacing: -1.76,
         color: ink,
       ),
       numeralKpi = TextStyle(
         fontFamily: kFontMono,
         fontSize: 22,
         height: 1,
         fontWeight: FontWeight.w700,
         letterSpacing: -0.66,
         color: ink,
       ),
       numeralSection = TextStyle(
         fontFamily: kFontMono,
         fontSize: 30,
         height: 1,
         fontWeight: FontWeight.w700,
         letterSpacing: -1.05,
         color: ink,
       ),
       numeralSub = TextStyle(
         fontFamily: kFontMono,
         fontSize: 20,
         height: 1,
         fontWeight: FontWeight.w700,
         color: ink,
       );

  final TextStyle data; // 12.5 / 1.0 / 500 — times, counts
  final TextStyle metric; // 15 / 1.0 / 600
  final TextStyle label; // 11 / 1.0 / 600 / +1.1 — CALLER uppercases
  final TextStyle groupLabel; // 10.5 / 1.0 / 600 / +1.16 — drawer groups
  final TextStyle fieldLabel; // 10 / 1.0 / 600 / +0.9 — dropdown labels
  final TextStyle micro; // 9.5 / 1.0 / 500 / +0.57
  final TextStyle numeralHero; // 44 / 1.0 / 700 / -1.76
  final TextStyle numeralKpi; // 22 / 1.0 / 700 / -0.66
  final TextStyle numeralSection; // 30 / 1.0 / 700 / -1.05
  final TextStyle numeralSub; // 20 / 1.0 / 700

  static final light = AppMonoType._of(
    ink: AppColors.ink,
    secondary: AppColors.ink60,
    tertiary: AppColors.ink40,
  );

  static final dark = AppMonoType._of(
    ink: AppColors.darkTextPrimary,
    secondary: AppColors.darkTextSecondary,
    tertiary: AppColors.darkTextTertiary,
  );

  @override
  AppMonoType copyWith({
    TextStyle? data,
    TextStyle? metric,
    TextStyle? label,
    TextStyle? groupLabel,
    TextStyle? fieldLabel,
    TextStyle? micro,
    TextStyle? numeralHero,
    TextStyle? numeralKpi,
    TextStyle? numeralSection,
    TextStyle? numeralSub,
  }) => AppMonoType(
    data: data ?? this.data,
    metric: metric ?? this.metric,
    label: label ?? this.label,
    groupLabel: groupLabel ?? this.groupLabel,
    fieldLabel: fieldLabel ?? this.fieldLabel,
    micro: micro ?? this.micro,
    numeralHero: numeralHero ?? this.numeralHero,
    numeralKpi: numeralKpi ?? this.numeralKpi,
    numeralSection: numeralSection ?? this.numeralSection,
    numeralSub: numeralSub ?? this.numeralSub,
  );

  @override
  AppMonoType lerp(ThemeExtension<AppMonoType>? other, double t) {
    if (other is! AppMonoType) return this;
    return AppMonoType(
      data: TextStyle.lerp(data, other.data, t)!,
      metric: TextStyle.lerp(metric, other.metric, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      groupLabel: TextStyle.lerp(groupLabel, other.groupLabel, t)!,
      fieldLabel: TextStyle.lerp(fieldLabel, other.fieldLabel, t)!,
      micro: TextStyle.lerp(micro, other.micro, t)!,
      numeralHero: TextStyle.lerp(numeralHero, other.numeralHero, t)!,
      numeralKpi: TextStyle.lerp(numeralKpi, other.numeralKpi, t)!,
      numeralSection: TextStyle.lerp(numeralSection, other.numeralSection, t)!,
      numeralSub: TextStyle.lerp(numeralSub, other.numeralSub, t)!,
    );
  }
}

extension AppMonoTypeX on ThemeData {
  AppMonoType get monoType =>
      extension<AppMonoType>() ??
      (brightness == Brightness.dark ? AppMonoType.dark : AppMonoType.light);
}
