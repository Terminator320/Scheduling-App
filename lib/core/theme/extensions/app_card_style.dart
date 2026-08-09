import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

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
