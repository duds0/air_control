import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colors for the current AC mode: soft background gradient + accent.
class ModePalette {
  const ModePalette(this.top, this.bottom, this.accent);
  final Color top;
  final Color bottom;
  final Color accent;

  static ModePalette of(String mode, bool power, Brightness b) {
    final dark = b == Brightness.dark;
    if (!power) {
      return dark
          ? const ModePalette(Color(0xFF17181B), Color(0xFF0F1012), Color(0xFF8A8F98))
          : const ModePalette(Color(0xFFF1F2F4), Color(0xFFE4E6EA), Color(0xFF7B818B));
    }
    switch (mode) {
      case 'FAN':
        return dark
            ? const ModePalette(Color(0xFF0E2A2A), Color(0xFF0A1B1C), Color(0xFF4FD1C5))
            : const ModePalette(Color(0xFFDDF6F1), Color(0xFFC6EBE4), Color(0xFF14A89A));
      case 'AIR_DRY':
        return dark
            ? const ModePalette(Color(0xFF2E2210), Color(0xFF1D160A), Color(0xFFF5B547))
            : const ModePalette(Color(0xFFFFF0D6), Color(0xFFFCE3B4), Color(0xFFD98A0B));
      default: // COOL
        return dark
            ? const ModePalette(Color(0xFF0C2338), Color(0xFF081522), Color(0xFF5BB5FF))
            : const ModePalette(Color(0xFFDCEEFF), Color(0xFFC3E0FB), Color(0xFF2B8BE6));
    }
  }
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2B8BE6),
      brightness: b,
    ),
    splashFactory: InkRipple.splashFactory,
  );
  return base.copyWith(
    textTheme: GoogleFonts.manropeTextTheme(base.textTheme).apply(
      bodyColor: dark ? const Color(0xFFF2F4F7) : const Color(0xFF14181F),
      displayColor: dark ? const Color(0xFFF2F4F7) : const Color(0xFF14181F),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
