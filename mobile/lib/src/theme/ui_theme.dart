import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Futuristic / Neon theme tuned for modern look and feel.
ThemeData buildAppTheme() {
  // Neon cyan / electric accent
  const accent = Color(0xFF00E5FF);
  const deep = Color(0xFF071427);
  final base = ThemeData.from(
      colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark),
      useMaterial3: true);

  final textTheme = GoogleFonts.poppinsTextTheme(base.textTheme).apply(
    bodyColor: Colors.white,
    displayColor: Colors.white,
  );

  return base.copyWith(
    scaffoldBackgroundColor: deep,
    textTheme: textTheme.copyWith(
      bodyLarge: const TextStyle(fontSize: 16, height: 1.4),
      bodyMedium: const TextStyle(fontSize: 14, height: 1.35),
      titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: Colors.white),
    ),
    // Elevated / primary buttons with stronger presence
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: accent,
        foregroundColor: Colors.black,
        elevation: 12,
        shadowColor: accent.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        backgroundColor: accent.withValues(alpha: 0.95),
        foregroundColor: Colors.black,
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: accent.withValues(alpha: 0.28)),
        foregroundColor: Colors.white,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent.withValues(alpha: 0.9), width: 1.8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)), // ignore: prefer_const_constructors
    ),
    cardTheme: base.cardTheme.copyWith(
      elevation: 10,
      color: Colors.white.withValues(alpha: 0.03),
      margin: const EdgeInsets.symmetric(vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: base.dialogTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
      backgroundColor: deep,
      selectedItemColor: accent,
      unselectedItemColor: Colors.white.withValues(alpha: 0.6),
    ),
  );
}

ThemeData buildDarkTheme() {
  // Slightly different accent for dark mode
  const accent = Color(0xFF7C3CFF);
  const deep = Color(0xFF050812);
  final base = ThemeData.from(
      colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark),
      useMaterial3: true);
  final textTheme = GoogleFonts.poppinsTextTheme(base.textTheme).apply(bodyColor: Colors.white, displayColor: Colors.white);

  return base.copyWith(
    scaffoldBackgroundColor: deep,
    textTheme: textTheme,
    appBarTheme: base.appBarTheme.copyWith(backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(filled: true, fillColor: Colors.white.withValues(alpha: 0.03)),
    cardTheme: base.cardTheme.copyWith(
      color: Colors.white.withValues(alpha: 0.03),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, elevation: 10, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, elevation: 10, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.white.withValues(alpha: 0.06)), foregroundColor: Colors.white)),
    bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(backgroundColor: deep, selectedItemColor: accent, unselectedItemColor: Colors.white.withValues(alpha: 0.6)),
  );
}