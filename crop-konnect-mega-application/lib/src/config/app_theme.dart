import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

ThemeData buildDarkTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF22C55E),
      brightness: Brightness.dark,
    ),
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF071512),
    useMaterial3: true,
    textTheme: GoogleFonts.plusJakartaSansTextTheme(),
  );
}

ThemeData buildLightTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF16A34A),
      brightness: Brightness.light,
    ),
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF0FDF4),
    useMaterial3: true,
    textTheme: GoogleFonts.plusJakartaSansTextTheme(),
  );
}
