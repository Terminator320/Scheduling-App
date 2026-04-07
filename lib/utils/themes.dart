import 'package:flutter/material.dart';

class Themes {
  // Light Theme
  final ThemeData lightTheme = ThemeData(
    useMaterial3: true,

    colorScheme: ColorScheme(
      brightness: Brightness.light,

      primary: Color(0xFF5A8FD8),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFD6E8FF),
      onPrimaryContainer: Color(0xFF0D3A6E),

      secondary: Color(0xFF72E8BC),
      onSecondary: Colors.black,
      secondaryContainer: Color(0xFFCEF7EB),
      onSecondaryContainer: Color(0xFF00432B),

      tertiary: Color(0xFF727CE8),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFDFE0FF),
      onTertiaryContainer: Color(0xFF1B1D6E),

      surface: Colors.white,
      onSurface: Colors.black,
      surfaceContainerHighest: Color(0xFFEDEDED),
      surfaceContainerLow: Color(0xFFF7F7F7),

      outline: Color(0xFFBDBDBD),
      outlineVariant: Color(0xFFE0E0E0),

      error: Color(0xFFB00020),
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),

      scrim: Colors.black,
      shadow: Colors.black,

      inverseSurface: Color(0xFF1E1E1E),
      onInverseSurface: Colors.white,
      inversePrimary: Color(0xFFADC8FF),

    ),

    // scaffoldBackgroundColor: Color(0xFFF4F4F4),

    textTheme: TextTheme(
      displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(fontSize: 14),
      bodySmall: TextStyle(fontSize: 12),
      labelLarge: TextStyle(fontWeight: FontWeight.w600),
      labelSmall: TextStyle(decoration: TextDecoration.underline),
    ).apply(
      bodyColor: Colors.black,
      displayColor: Colors.black,
    ),


    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      surfaceTintColor: Colors.transparent,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 3,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFF5A8FD8), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFFB00020)),
      ),
    ),


    dividerTheme: DividerThemeData(
      thickness: 1,
      color: Color(0xFFE0E0E0),
    ),

    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      side: BorderSide(color: Color(0xFFE0E0E0)),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),


    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    ),


    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      backgroundColor: Colors.white,
    ),

  );



  // Dark Theme
   final ThemeData darkTheme = ThemeData(
    useMaterial3: true,

    colorScheme: ColorScheme(
      brightness: Brightness.dark,

      primary: Color(0xFF5A8FD8),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF0D3A6E),
      onPrimaryContainer: Color(0xFFD6E8FF),

      secondary: Color(0xFF4CCFA5),
      onSecondary: Colors.black,
      secondaryContainer: Color(0xFF00432B),
      onSecondaryContainer: Color(0xFFCEF7EB),

      tertiary: Color(0xFF5C66D6),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFF1B1D6E),
      onTertiaryContainer: Color(0xFFDFE0FF),

      surface: Color(0xFF1E1E1E),
      onSurface: Colors.white,
      surfaceContainerHighest: Color(0xFF2C2C2C),
      surfaceContainerLow: Color(0xFF181818),

      outline: Color(0xFF555555),
      outlineVariant: Color(0xFF3A3A3A),

      error: Colors.redAccent,
      onError: Colors.black,
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),

      scrim: Colors.black,
      shadow: Colors.black,

      inverseSurface: Colors.white,
      onInverseSurface: Colors.black,
      inversePrimary: Color(0xFF5A8FD8),
    ),

    // scaffoldBackgroundColor: Color(0xFF121212),

     textTheme: TextTheme(
       displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
       headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
       titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
       bodyMedium: TextStyle(fontSize: 14),
       bodySmall: TextStyle(fontSize: 12),
       labelLarge: TextStyle(fontWeight: FontWeight.w600),
       labelSmall: TextStyle(decoration: TextDecoration.underline),
     ).apply(
       bodyColor: Colors.white,
       displayColor: Colors.white,
     ),


    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 3,
      color: Color(0xFF1E1E1E),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),

     inputDecorationTheme: InputDecorationTheme(
       filled: true,
       fillColor: Color(0xFF2C2C2C),
       border: OutlineInputBorder(
         borderRadius: BorderRadius.circular(10),
         borderSide: BorderSide.none,
       ),
       enabledBorder: OutlineInputBorder(
         borderRadius: BorderRadius.circular(10),
         borderSide: BorderSide.none,
       ),
       focusedBorder: OutlineInputBorder(
         borderRadius: BorderRadius.circular(10),
         borderSide: BorderSide(color: Color(0xFF5A8FD8), width: 1.5),
       ),
       errorBorder: OutlineInputBorder(
         borderRadius: BorderRadius.circular(10),
         borderSide: BorderSide(color: Colors.redAccent),
       ),
       hintStyle: TextStyle(color: Color(0xFF888888)),
     ),

     dividerTheme: DividerThemeData(
       thickness: 1,
       color: Color(0xFF3A3A3A),
     ),

     chipTheme: ChipThemeData(
       shape: RoundedRectangleBorder(
         borderRadius: BorderRadius.circular(8),
       ),
       side: BorderSide(color: Color(0xFF3A3A3A)),
     ),

     bottomSheetTheme: BottomSheetThemeData(
       backgroundColor: Color(0xFF1E1E1E),
       shape: RoundedRectangleBorder(
         borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
       ),
     ),

     dialogTheme: DialogThemeData(
       shape: RoundedRectangleBorder(
         borderRadius: BorderRadius.circular(16),
       ),
       backgroundColor: Color(0xFF1E1E1E),
     ),

     snackBarTheme: SnackBarThemeData(
       behavior: SnackBarBehavior.floating,
       backgroundColor: Color(0xFF2C2C2C),
       contentTextStyle: TextStyle(color: Colors.white),
       shape: RoundedRectangleBorder(
         borderRadius: BorderRadius.circular(10),
       ),
     ),


  );
}