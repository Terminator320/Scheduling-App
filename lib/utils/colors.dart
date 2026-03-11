import 'package:flutter/material.dart';

Color kPurple = Color(0xCC6D29F6);

const List<Color> kEmployeePickerColors = [
  Colors.black,
  Color(0xFF1D8CFF),
  Color(0xFF42C86A),
  Color(0xFFF4C20D),
  Color(0xFFFF3B30),
  Color(0xFF7DC9FF),
  Color(0xFFB455FF),
  Color(0xFF5C6BFF),
  Color(0xFFFF2D55),
];

Color employeeCardColor(Color color) {
  return Color.alphaBlend(color.withOpacity(0.22), Colors.white);
}

Color employeeCardTextColor(Color color) {
  final brightness = ThemeData.estimateBrightnessForColor(color);
  return brightness == Brightness.dark ? Colors.white : Colors.black;
}

Color employeeCardSubtextColor(Color color) {
  final brightness = ThemeData.estimateBrightnessForColor(color);
  return brightness == Brightness.dark ? Colors.white70 : Colors.black54;
}