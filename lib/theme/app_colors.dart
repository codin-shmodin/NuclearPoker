import 'package:flutter/material.dart';

/// Central palette. A warm, premium "felt + gold" look — deliberately not the
/// flat, cheap feel of typical poker apps.
abstract class AppColors {
  static const Color background = Color(0xFF0E1116);
  static const Color backgroundTop = Color(0xFF1A2230);

  static const Color feltDark = Color(0xFF0B3D2E);
  static const Color feltLight = Color(0xFF15805F);
  static const Color feltCenter = Color(0xFF1C6B4F);
  static const Color feltEdge = Color(0xFF0A2E22);
  static const Color feltRail = Color(0xFF3A2A1A);

  static const Color gold = Color(0xFFE8C26A);
  static const Color goldBright = Color(0xFFF6D98A);
  static const Color goldDeep = Color(0xFFB8893B);

  static const Color cardFace = Color(0xFFF7F4EC);
  static const Color cardBackA = Color(0xFF7A1F2B);
  static const Color cardBackB = Color(0xFFB23A48);
  static const Color cardRed = Color(0xFFC0392B);
  static const Color cardBlack = Color(0xFF1C2230);

  static const Color textPrimary = Color(0xFFF4F6FA);
  static const Color textMuted = Color(0xFF9AA7B8);

  static const Color chipRed = Color(0xFFD64550);
  static const Color chipBlue = Color(0xFF3B7DD8);
  static const Color chipGreen = Color(0xFF2E9E5B);
  static const Color chipBlack = Color(0xFF23272E);

  static const Color win = Color(0xFF4BD37B);
  static const Color danger = Color(0xFFE05A5A);

  /// Aggressive action (bet/raise = "pot").
  static const Color potPurple = Color(0xFF9B5CF6);
  static const Color potPurpleDeep = Color(0xFF7C3AED);
}
