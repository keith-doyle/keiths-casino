import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.indigo,
    );
  }

  static const BoxDecoration gradientHeroDecoration = BoxDecoration(
    color: Colors.indigo,
  );

  static const BoxDecoration softCardDecoration = BoxDecoration(
    color: Colors.white,
  );
}