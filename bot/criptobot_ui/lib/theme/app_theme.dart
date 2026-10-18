import 'package:flutter/material.dart';

class AppTheme {
  // Paleta de colores oscuros de alta fidelidad institucional (Estilo Terminal Cuantitativa)
  static const Color fondoPrincipal = Color(0xFF0B0E14);
  static const Color fondoTarjeta = Color(0xFF151922);
  static const Color fondoTarjetaSecundaria = Color(0xFF1C2230);
  static const Color bordeTarjeta = Color(0xFF262E40);

  static const Color verdeGanancia = Color(0xFF00E676);
  static const Color verdeSuave = Color(0xFF1B5E20);
  static const Color rojoPerdida = Color(0xFFFF5252);
  static const Color azulCyan = Color(0xFF00E5FF);
  static const Color amarilloAdvertencia = Color(0xFFFFB300);
  static const Color textoPrincipal = Color(0xFFF0F4F8);
  static const Color textoSecundario = Color(0xFF8A9BA8);

  static ThemeData get temaOscuro {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: fondoPrincipal,
      primaryColor: azulCyan,
      cardTheme: CardThemeData(
        color: fondoTarjeta,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: bordeTarjeta, width: 1),
        ),
        elevation: 0,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: fondoPrincipal,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textoPrincipal,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: textoPrincipal),
        bodySmall: TextStyle(color: textoSecundario),
      ),
    );
  }
}
