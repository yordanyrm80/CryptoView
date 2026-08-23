import 'package:flutter/material.dart';

/// Centralized color palette for CryptoView dark theme design system
class AppColors {
  AppColors._();

  // Backgrounds
  static const Color background = Color(0xFF0C0F14);
  static const Color surface = Color(0xFF171A22);
  static const Color card = Color(0xFF12161F);
  static const Color cardSelected = Color(0xFF1D2430);

  // Borders and Dividers
  static const Color border = Color(0xFF263238);
  static const Color divider = Color(0xFF1E2738);
  static const Color gridLine = Color(0xFF161A1E);

  // Brand and Accent Colors
  static const Color primary = Color(0xFF00E6B8);      // Electric Cyan
  static const Color secondary = Color(0xFFF0B90B);    // Crypto Gold

  // Trading Actions
  static const Color bull = Color(0xFF0ECB81);         // Emerald Green (Buy / Up)
  static const Color bear = Color(0xFFF6465D);         // Neon Red (Sell / Down)
  static const Color buyOrder = Color(0xFF29B6F6);     // Light Blue for buy order markers

  // Typography
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF90A4AE);
  static const Color textMuted = Color(0xFF546E7A);
}
