import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

TextTheme _buildTextTheme({
  required Color ink, // titles
  required Color body, // body copy
  required Color secondary, // Ink 60
  required Color caption, // Ink 25
}) {
  TextStyle s(
    double size,
    double height,
    FontWeight weight,
    double tracking,
    Color colour,
  ) => TextStyle(
    fontFamily: kFontSans,
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: tracking,
    color: colour,
  );

  return TextTheme(
    displayLarge: s(26, 1.1, FontWeight.w700, -0.65, ink),
    displayMedium: s(22, 1.2, FontWeight.w700, -0.55, ink),
    displaySmall: s(19, 1.25, FontWeight.w700, -0.38, ink),
    headlineLarge: s(22, 1.2, FontWeight.w700, -0.55, ink), // sheet title
    headlineMedium: s(19, 1.25, FontWeight.w700, -0.38, ink), // dialog title
    headlineSmall: s(17, 1.2, FontWeight.w600, -0.34, ink), // section title
    titleLarge: s(17, 1.2, FontWeight.w600, -0.34, ink), // app bar
    titleMedium: s(15, 1.25, FontWeight.w600, -0.15, ink), // row + card title
    titleSmall: s(13.5, 1.3, FontWeight.w600, 0, ink), // sub-row title
    bodyLarge: s(15, 1.4, FontWeight.w400, 0, ink), // inputs, lead body
    bodyMedium: s(13.5, 1.45, FontWeight.w400, 0, body), // body
    bodySmall: s(12.5, 1.3, FontWeight.w400, 0, secondary), // secondary
    labelLarge: s(14, 1, FontWeight.w600, 0, ink), // button, tab
    labelMedium: s(11.5, 1.45, FontWeight.w400, 0, caption), // caption
    labelSmall: s(11, 1.5, FontWeight.w600, 0, ink), // chip label
  );
}

ThemeData? _lightThemeCache;
ThemeData lightTheme() => _lightThemeCache ??= _buildLightTheme();

ThemeData? _darkThemeCache;
ThemeData darkTheme() => _darkThemeCache ??= _buildDarkTheme();

ThemeData _buildLightTheme() {
  const cs = ColorScheme.light(
    primary: AppColors.blue,
    onPrimary: Colors.white,
    primaryContainer: AppColors.blueTint,
    onPrimaryContainer: AppColors.blue,
    secondary: AppColors.green,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.greenFill,
    onSecondaryContainer: AppColors.greenText,
    tertiary: AppColors.amber, // WARNING slot — never success
    onTertiary: Colors.white,
    tertiaryContainer: AppColors.amberFill,
    onTertiaryContainer: AppColors.amberText,
    error: AppColors.red,
    onError: Colors.white,
    errorContainer: AppColors.redFill,
    onErrorContainer: AppColors.redText,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.ink60,
    outline: AppColors.hairline,
    outlineVariant: AppColors.border,
    surfaceContainerLowest: AppColors.surfaceHover,
    surfaceContainerLow: AppColors.sheet,
    surfaceContainer: AppColors.paper,
    surfaceContainerHigh: AppColors.track,
    surfaceContainerHighest: AppColors.paper2,
    inverseSurface: AppColors.ink, // notice / toast background
    onInverseSurface: AppColors.darkTextPrimary,
    inversePrimary: AppColors.darkBlueText,
    surfaceTint: Colors.transparent, // kill M3 elevation tinting
    scrim: AppColors.ink,
    shadow: AppColors.ink,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    fontFamily: kFontSans,
    extensions: [
      AppStatusColors.light,
      AppCardStyle.light,
      AppPalette.light,
      AppMonoType.light,
    ],
    scaffoldBackgroundColor: AppColors.paper,
    textTheme: _buildTextTheme(
      ink: AppColors.ink,
      body: AppColors.ink80,
      secondary: AppColors.ink60,
      caption: AppColors.ink25,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.blue,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kFontSans,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp16,
        vertical: AppSpacing.sp12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        borderSide: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        borderSide: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        borderSide: const BorderSide(color: AppColors.red, width: 2),
      ),
      hintStyle: const TextStyle(
        fontFamily: kFontSans,
        fontSize: 13,
        color: AppColors.ink40,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.r8),
        ),
        textStyle: const TextStyle(
          fontFamily: kFontSans,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.blue,
        side: const BorderSide(color: AppColors.blue, width: 1.5),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.r8),
        ),
        textStyle: const TextStyle(
          fontFamily: kFontSans,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      modalBarrierColor: Color(0x730B1A33),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.r16),
        ),
      ),
      elevation: 0,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(AppRadius.r16),
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.hairline,
      thickness: 1,
      space: 0,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.blue,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
    ),
  );
}

ThemeData _buildDarkTheme() {
  const cs = ColorScheme.dark(
    primary: AppColors.darkBlueFill, // buttons stay saturated
    onPrimary: Colors.white,
    primaryContainer: Color(0x294B90F7), // 16% of #4B90F7
    onPrimaryContainer: AppColors.darkBlueOnTint,
    secondary: AppColors.darkGreen,
    onSecondary: Colors.white,
    secondaryContainer: Color(0x292BC48E),
    onSecondaryContainer: AppColors.darkGreenText,
    tertiary: AppColors.darkAmber,
    onTertiary: Color(0xFF1A1000), // near-black on amber
    tertiaryContainer: Color(0x29F1A83C),
    onTertiaryContainer: AppColors.darkAmber,
    error: AppColors.darkRed, // lifted — Material reads this as foreground
    onError: Color(0xFF1C060A),
    errorContainer: Color(0x29FF6076),
    onErrorContainer: AppColors.darkRedText,
    surface: AppColors.darkCard,
    onSurface: AppColors.darkTextPrimary,
    onSurfaceVariant: AppColors.darkTextSecondary,
    outline: Color(0x12FFFFFF), // 7% white hairline
    outlineVariant: Color(0x0FFFFFFF), // 6% white row divider
    surfaceContainerLowest: AppColors.darkPage,
    surfaceContainerLow: AppColors.darkSheet,
    surfaceContainer: AppColors.darkCard,
    surfaceContainerHigh: AppColors.darkSheetRow,
    surfaceContainerHighest: AppColors.darkNotice,
    inverseSurface: AppColors.darkNotice,
    onInverseSurface: AppColors.darkTextPrimary,
    inversePrimary: AppColors.blue,
    surfaceTint: Colors.transparent,
    scrim: Color(0xFF040810),
    shadow: Colors.black,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    fontFamily: kFontSans,
    extensions: [
      AppStatusColors.dark,
      AppCardStyle.dark,
      AppPalette.dark,
      AppMonoType.dark,
    ],
    scaffoldBackgroundColor: AppColors.darkPage,
    textTheme: _buildTextTheme(
      ink: AppColors.darkTextPrimary,
      body: const Color(0xFFC5D0E2),
      secondary: AppColors.darkTextSecondary,
      caption: AppColors.darkTextMuted,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkBlueFill,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kFontSans,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkCard,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp16,
        vertical: AppSpacing.sp12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        borderSide: const BorderSide(color: Color(0x12FFFFFF), width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        borderSide: const BorderSide(color: Color(0x12FFFFFF), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        borderSide: const BorderSide(color: AppColors.darkBlueText, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        borderSide: const BorderSide(color: AppColors.darkRed, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        borderSide: const BorderSide(color: AppColors.darkRed, width: 2),
      ),
      hintStyle: const TextStyle(
        fontFamily: kFontSans,
        fontSize: 13,
        color: AppColors.darkTextMuted,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.darkBlueFill,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.r8),
        ),
        textStyle: const TextStyle(
          fontFamily: kFontSans,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.darkBlueText,
        side: const BorderSide(color: AppColors.darkBlueText, width: 1.5),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.r8),
        ),
        textStyle: const TextStyle(
          fontFamily: kFontSans,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.darkSheet,
      modalBarrierColor: Color(0x8C040810),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.r16),
        ),
      ),
      elevation: 0,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.darkSheet,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(AppRadius.r16),
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0x0FFFFFFF),
      thickness: 1,
      space: 0,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.darkBlueFill,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
    ),
  );
}
