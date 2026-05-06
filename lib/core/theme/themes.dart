import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'design_tokens.dart';

TextTheme _buildTextTheme(Color onSurface, Color subtle) {
  final base = GoogleFonts.interTextTheme();
  return base.copyWith(
    displayLarge: base.displayLarge?.copyWith(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: onSurface),
    headlineLarge: base.headlineLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: onSurface),
    headlineMedium: base.headlineMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600, color: onSurface),
    titleMedium: base.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: onSurface),
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w400, color: onSurface),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: subtle),
    bodySmall: base.bodySmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w400, color: subtle),
    labelLarge: base.labelLarge?.copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: onSurface),
    labelMedium: base.labelMedium?.copyWith(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: subtle),
    labelSmall: base.labelSmall?.copyWith(fontSize: 9, fontWeight: FontWeight.w500, letterSpacing: 0.5, color: subtle),
  );
}

ThemeData lightTheme() {
  final cs = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primarySurface,
    onPrimaryContainer: AppColors.primaryDark,
    secondary: AppColors.success,
    onSecondary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.onSurface,
    onSurfaceVariant: AppColors.subtle,
    outline: AppColors.outline,
    outlineVariant: AppColors.surfaceAlt,
    error: AppColors.error,
    onError: Colors.white,
    errorContainer: AppColors.errorTint,
    onErrorContainer: AppColors.errorText,
    surfaceContainerHighest: AppColors.surfaceAlt,
    inversePrimary: AppColors.primaryTint,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: _buildTextTheme(AppColors.onSurface, AppColors.subtle),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r8)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp16, vertical: AppSpacing.sp12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.r12), borderSide: const BorderSide(color: AppColors.outline, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.r12), borderSide: const BorderSide(color: AppColors.outline, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.r12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.r12), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
      hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r8)),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r8)),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.r16))),
      elevation: 0,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(AppRadius.r16))),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.outline, thickness: 1, space: 0),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.rFull)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.rFull)),
    ),
  );
}

ThemeData darkTheme() {
  final cs = ColorScheme.dark(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.darkPrimaryTint,
    onPrimaryContainer: AppColors.darkPrimaryOnDark,
    secondary: AppColors.success,
    onSecondary: Colors.white,
    surface: AppColors.darkSurface,
    onSurface: AppColors.darkOnSurface,
    onSurfaceVariant: AppColors.darkSubtle,
    outline: AppColors.darkOutline,
    outlineVariant: AppColors.darkSurfaceAlt,
    error: AppColors.error,
    onError: Colors.white,
    errorContainer: AppColors.darkErrorTint,
    onErrorContainer: AppColors.darkErrorText,
    surfaceContainerHighest: AppColors.darkSurfaceAlt,
    inversePrimary: AppColors.darkPrimaryTint,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: AppColors.darkBackground,
    textTheme: _buildTextTheme(AppColors.darkOnSurface, AppColors.darkSubtle),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r8)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp16, vertical: AppSpacing.sp12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.r12), borderSide: const BorderSide(color: AppColors.darkSurfaceAlt, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.r12), borderSide: const BorderSide(color: AppColors.darkSurfaceAlt, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.r12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.r12), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
      hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.darkMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r8)),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r8)),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.r16))),
      elevation: 0,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(AppRadius.r16))),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.darkOutline, thickness: 1, space: 0),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.rFull)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.rFull)),
    ),
  );
}
