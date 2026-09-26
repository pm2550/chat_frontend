import 'package:flutter/material.dart';

class AppColors {
  // PM chat brand palette
  static const Color primary = Color(0xFF625BD6);
  static const Color primaryDark = Color(0xFF38346F);
  static const Color primaryLight = Color(0xFF9992ED);

  static const Color secondary = Color(0xFF0FAE96);
  static const Color secondaryDark = Color(0xFF047A6F);
  static const Color accent = Color(0xFFFF7A59);
  static const Color accentGold = Color(0xFFF4B740);

  static const Color ink = Color(0xFF24253D);
  static const Color cloud = Color(0xFFF7F7FB);
  static const Color mist = Color(0xFFEDEDF5);
  static const Color pixelBlue = Color(0xFFEFEDFC);
  static const Color pixelMint = Color(0xFFE6F8F4);
  static const Color pixelCoral = Color(0xFFFFEEE9);

  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = cloud;
  static const Color card = Color(0xFFFFFFFF);

  static const Color textPrimary = ink;
  static const Color textSecondary = Color(0xFF696B82);
  static const Color textTertiary = Color(0xFF9294A8);
  static const Color textWhite = Color(0xFFFFFFFF);

  static const Color border = Color(0xFFE1E2EC);
  static const Color borderLight = Color(0xFFEBECF3);

  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // 在线状态颜色
  static const Color online = Color(0xFF10B981);
  static const Color away = Color(0xFFF59E0B);
  static const Color busy = Color(0xFFEF4444);
  static const Color offline = Color(0xFF6B7280);

  static const Color messageReceived = Color(0xFFFFFFFF);
  static const Color messageSent = primary;
  static const Color messageTime = Color(0xFF8A9AB0);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary, primaryLight],
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [cloud, Color(0xFFF3F2FA), cloud],
  );

  static const LinearGradient messageGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, Color(0xFF7770E3)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentGold],
  );

  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0x0924253D),
    blurRadius: 18,
    offset: Offset(0, 5),
  );

  static const BoxShadow appBarShadow = BoxShadow(
    color: Color(0x0624253D),
    blurRadius: 10,
    offset: Offset(0, 4),
  );
}
