import 'package:flutter/material.dart';

class PMSpacing {
  const PMSpacing._();

  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

class PMRadius {
  const PMRadius._();

  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double pill = 999;
}

class PMElevation {
  const PMElevation._();

  static const subtle = BoxShadow(
    color: Color(0x0A0B1F3A),
    blurRadius: 8,
    offset: Offset(0, 2),
  );
  static const card = BoxShadow(
    color: Color(0x120B1F3A),
    blurRadius: 14,
    offset: Offset(0, 6),
  );
  static const hover = BoxShadow(
    color: Color(0x1A0B1F3A),
    blurRadius: 24,
    offset: Offset(0, 10),
  );
  static const float = BoxShadow(
    color: Color(0x220B1F3A),
    blurRadius: 32,
    offset: Offset(0, 16),
  );
}

class PMMotion {
  const PMMotion._();

  static const fast = Duration(milliseconds: 120);
  static const medium = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 360);
  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveEmphasis = Curves.easeOutBack;
}
