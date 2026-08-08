import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

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
