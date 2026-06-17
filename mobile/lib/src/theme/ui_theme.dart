import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData buildAppTheme() {
  const seed = Color(0xFF1C7C73);
  final base = ThemeData.from(
      colorScheme: ColorScheme.fromSeed(seedColor: seed), useMaterial3: true);

  final textTheme = GoogleFonts.poppinsTextTheme(base.textTheme).apply(
    bodyColor: const Color(0xFF0F2E2D),
    displayColor: const Color(0xFF0F2E2D),
  );

  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFFF4F8F7),
    appBarTheme: base.appBarTheme.copyWith(
      centerTitle: false,
      backgroundColor: const Color(0xFFEDF7F5),
      foregroundColor: const Color(0xFF0F2E2D),
      elevation: 0,
      titleTextStyle:
          textTheme.titleLarge?.copyWith(color: const Color(0xFF0F2E2D)),
    ),
    textTheme: textTheme.copyWith(
      bodyLarge: const TextStyle(fontSize: 16),
      bodyMedium: const TextStyle(fontSize: 14),
      titleLarge: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: seed,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 6,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 6,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: seed.withOpacity(0.22)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: seed.withOpacity(0.18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: seed, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    cardTheme: base.cardTheme.copyWith(
      elevation: 0,
      color: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

ThemeData buildDarkTheme() {
  const seed = Color(0xFF1C7C73);
  final base = ThemeData.from(
      colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
      useMaterial3: true);
  final textTheme = GoogleFonts.poppinsTextTheme(base.textTheme)
      .apply(bodyColor: Colors.white, displayColor: Colors.white);

  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFF081018),
    textTheme: textTheme,
    appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: const Color(0xFF07131A), foregroundColor: Colors.white, elevation: 0),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(filled: true, fillColor: const Color(0xFF0B1B1F)),
    cardTheme: base.cardTheme.copyWith(color: Colors.transparent),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: seed)),
  );
}
