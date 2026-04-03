import 'package:flutter/material.dart';

class Themes {
  // Light Theme
  final ThemeData lightTheme = ThemeData(
    useMaterial3: true,

    colorScheme: ColorScheme(
      brightness: Brightness.light,

      primary: Color(0xFF82A7E8),
      onPrimary: Colors.white,

      secondary: Color(0xFF72E8BC),
      onSecondary: Colors.black,

      tertiary: Color(0xFF727CE8),
      onTertiary: Colors.white,

      surface: Colors.white,
      onSurface: Colors.black,

      error: Colors.red,
      onError: Colors.white,
    ),

    scaffoldBackgroundColor: Color(0xFF99B7E4),

    textTheme: TextTheme(
      displayLarge: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(fontSize: 14),
      bodySmall: TextStyle(fontSize: 12),
      labelLarge: TextStyle(fontWeight: FontWeight.w600),
      labelSmall: TextStyle(
        decoration: TextDecoration.underline,
        decorationThickness: 2,
      ),
    ).apply(
      bodyColor: Colors.black,
      displayColor: Colors.black,
    ),

    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: true,
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
    ),

    dividerTheme: DividerThemeData(
      thickness: 1,
      color: Color(0xFF727CE8),
    ),
  );



  // Dark Theme
   final ThemeData darkTheme = ThemeData(
    useMaterial3: true,

    colorScheme: ColorScheme(
      brightness: Brightness.dark,

      primary: Color(0xFF5A8FD8),
      onPrimary: Colors.white,

      secondary: Color(0xFF4CCFA5),
      onSecondary: Colors.black,

      tertiary: Color(0xFF5C66D6),
      onTertiary: Colors.white,

      surface: Color(0xFF1E1E1E),
      onSurface: Colors.white,

      error: Colors.redAccent,
      onError: Colors.black,
    ),

    scaffoldBackgroundColor: Color(0xFF121212),

    textTheme: TextTheme(
      displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(fontSize: 14),
      bodySmall: TextStyle(fontSize: 12),
      labelLarge: TextStyle(fontWeight: FontWeight.w600),
    ).apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),

    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: true,
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFF1E1E1E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    ),

    dividerTheme: DividerThemeData(thickness: 1),
  );
}