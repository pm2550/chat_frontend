import 'dart:math' as math;

import 'package:flutter/material.dart';

enum PMSymbol {
  chat,
  contacts,
  workspace,
  ai,
  profile,
  members,
  files,
  folder,
  terminal,
  add,
  send,
  mic,
  micOff,
  emoji,
  sticker,
  settings,
  call,
  callEnd,
  video,
  videoOff,
  search,
  more,
  back,
  close,
  chevronRight,
  link,
  camera,
  image,
  location,
  poll,
}

class PMSymbolIcon extends StatelessWidget {
  const PMSymbolIcon(
    this.symbol, {
    super.key,
    this.size = 20,
    this.color,
  });

  final PMSymbol symbol;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? IconTheme.of(context).color ?? Colors.black;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _PMSymbolPainter(symbol, resolvedColor),
      ),
    );
  }
}

class _PMSymbolPainter extends CustomPainter {
  const _PMSymbolPainter(this.symbol, this.color);

  final PMSymbol symbol;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.095
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (symbol) {
      case PMSymbol.chat:
        _chat(canvas, size, stroke);
      case PMSymbol.contacts:
        _contacts(canvas, size, stroke, fill);
      case PMSymbol.workspace:
        _workspace(canvas, size, stroke);
      case PMSymbol.ai:
        _ai(canvas, size, stroke, fill);
      case PMSymbol.profile:
        _profile(canvas, size, stroke);
      case PMSymbol.members:
        _contacts(canvas, size, stroke, fill);
      case PMSymbol.files:
        _file(canvas, size, stroke);
      case PMSymbol.folder:
        _folder(canvas, size, stroke);
      case PMSymbol.terminal:
        _terminal(canvas, size, stroke);
      case PMSymbol.add:
        _add(canvas, size, stroke);
      case PMSymbol.send:
        _send(canvas, size, stroke);
      case PMSymbol.mic:
        _mic(canvas, size, stroke);
      case PMSymbol.micOff:
        _mic(canvas, size, stroke);
        _slash(canvas, size, stroke);
      case PMSymbol.emoji:
        _emoji(canvas, size, stroke);
      case PMSymbol.sticker:
        _sticker(canvas, size, stroke);
      case PMSymbol.settings:
        _settings(canvas, size, stroke);
      case PMSymbol.call:
        _call(canvas, size, stroke);
      case PMSymbol.callEnd:
        _call(canvas, size, stroke);
        _slash(canvas, size, stroke);
      case PMSymbol.video:
        _video(canvas, size, stroke);
      case PMSymbol.videoOff:
        _video(canvas, size, stroke);
        _slash(canvas, size, stroke);
      case PMSymbol.search:
        _search(canvas, size, stroke);
      case PMSymbol.more:
        _more(canvas, size, fill);
      case PMSymbol.back:
        _back(canvas, size, stroke);
      case PMSymbol.close:
        _close(canvas, size, stroke);
      case PMSymbol.chevronRight:
        _chevronRight(canvas, size, stroke);
      case PMSymbol.link:
        _link(canvas, size, stroke);
      case PMSymbol.camera:
        _camera(canvas, size, stroke);
      case PMSymbol.image:
        _image(canvas, size, stroke);
      case PMSymbol.location:
        _location(canvas, size, stroke, fill);
      case PMSymbol.poll:
        _poll(canvas, size, stroke);
    }
  }

  void _chat(Canvas canvas, Size size, Paint stroke) {
    final rect = Rect.fromLTWH(
      size.width * 0.12,
      size.height * 0.18,
      size.width * 0.76,
      size.height * 0.56,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.12)),
      stroke,
    );
    final tail = Path()
      ..moveTo(size.width * 0.34, size.height * 0.74)
      ..lineTo(size.width * 0.22, size.height * 0.90)
      ..lineTo(size.width * 0.50, size.height * 0.74);
    canvas.drawPath(tail, stroke);
    for (final x in [0.34, 0.50, 0.66]) {
      canvas.drawCircle(Offset(size.width * x, size.height * 0.47),
          size.width * 0.035, stroke);
    }
  }

  void _contacts(Canvas canvas, Size size, Paint stroke, Paint fill) {
    canvas.drawCircle(
      Offset(size.width * 0.50, size.height * 0.36),
      size.width * 0.14,
      stroke,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * 0.28,
        size.height * 0.52,
        size.width * 0.44,
        size.height * 0.32,
      ),
      3.22,
      3.20,
      false,
      stroke,
    );
    canvas.drawCircle(
      Offset(size.width * 0.24, size.height * 0.44),
      size.width * 0.09,
      stroke,
    );
    canvas.drawCircle(
      Offset(size.width * 0.76, size.height * 0.44),
      size.width * 0.09,
      stroke,
    );
    canvas.drawCircle(Offset(size.width * 0.50, size.height * 0.36),
        size.width * 0.025, fill);
  }

  void _workspace(Canvas canvas, Size size, Paint stroke) {
    _folder(canvas, size, stroke);
    final nodePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (final offset in [
      Offset(size.width * 0.34, size.height * 0.62),
      Offset(size.width * 0.50, size.height * 0.54),
      Offset(size.width * 0.66, size.height * 0.62),
    ]) {
      canvas.drawCircle(offset, size.width * 0.035, nodePaint);
    }
    canvas.drawLine(
      Offset(size.width * 0.34, size.height * 0.62),
      Offset(size.width * 0.50, size.height * 0.54),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.66, size.height * 0.62),
      Offset(size.width * 0.50, size.height * 0.54),
      stroke,
    );
  }

  void _ai(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final body = Rect.fromLTWH(
      size.width * 0.20,
      size.height * 0.28,
      size.width * 0.60,
      size.height * 0.46,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(size.width * 0.10)),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.50, size.height * 0.18),
      Offset(size.width * 0.50, size.height * 0.28),
      stroke,
    );
    canvas.drawCircle(
      Offset(size.width * 0.50, size.height * 0.15),
      size.width * 0.035,
      fill,
    );
    canvas.drawCircle(
      Offset(size.width * 0.40, size.height * 0.48),
      size.width * 0.035,
      fill,
    );
    canvas.drawCircle(
      Offset(size.width * 0.60, size.height * 0.48),
      size.width * 0.035,
      fill,
    );
    canvas.drawLine(
      Offset(size.width * 0.42, size.height * 0.62),
      Offset(size.width * 0.58, size.height * 0.62),
      stroke,
    );
  }

  void _profile(Canvas canvas, Size size, Paint stroke) {
    canvas.drawCircle(
      Offset(size.width * 0.50, size.height * 0.34),
      size.width * 0.16,
      stroke,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * 0.22,
        size.height * 0.54,
        size.width * 0.56,
        size.height * 0.34,
      ),
      3.22,
      3.20,
      false,
      stroke,
    );
  }

  void _file(Canvas canvas, Size size, Paint stroke) {
    final path = Path()
      ..moveTo(size.width * 0.26, size.height * 0.12)
      ..lineTo(size.width * 0.62, size.height * 0.12)
      ..lineTo(size.width * 0.78, size.height * 0.28)
      ..lineTo(size.width * 0.78, size.height * 0.86)
      ..lineTo(size.width * 0.26, size.height * 0.86)
      ..close();
    canvas.drawPath(path, stroke);
    canvas.drawLine(
      Offset(size.width * 0.62, size.height * 0.12),
      Offset(size.width * 0.62, size.height * 0.30),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.62, size.height * 0.30),
      Offset(size.width * 0.78, size.height * 0.30),
      stroke,
    );
    for (final y in [0.48, 0.62]) {
      canvas.drawLine(
        Offset(size.width * 0.38, size.height * y),
        Offset(size.width * 0.66, size.height * y),
        stroke,
      );
    }
  }

  void _folder(Canvas canvas, Size size, Paint stroke) {
    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.30)
      ..lineTo(size.width * 0.38, size.height * 0.30)
      ..lineTo(size.width * 0.46, size.height * 0.40)
      ..lineTo(size.width * 0.88, size.height * 0.40)
      ..lineTo(size.width * 0.88, size.height * 0.78)
      ..lineTo(size.width * 0.12, size.height * 0.78)
      ..close();
    canvas.drawPath(path, stroke);
  }

  void _terminal(Canvas canvas, Size size, Paint stroke) {
    final rect = Rect.fromLTWH(
      size.width * 0.14,
      size.height * 0.18,
      size.width * 0.72,
      size.height * 0.64,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.10)),
      stroke,
    );
    final prompt = Path()
      ..moveTo(size.width * 0.30, size.height * 0.42)
      ..lineTo(size.width * 0.42, size.height * 0.50)
      ..lineTo(size.width * 0.30, size.height * 0.58);
    canvas.drawPath(prompt, stroke);
    canvas.drawLine(
      Offset(size.width * 0.50, size.height * 0.60),
      Offset(size.width * 0.68, size.height * 0.60),
      stroke,
    );
  }

  void _add(Canvas canvas, Size size, Paint stroke) {
    canvas.drawLine(
      Offset(size.width * 0.50, size.height * 0.22),
      Offset(size.width * 0.50, size.height * 0.78),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.22, size.height * 0.50),
      Offset(size.width * 0.78, size.height * 0.50),
      stroke,
    );
  }

  void _send(Canvas canvas, Size size, Paint stroke) {
    final path = Path()
      ..moveTo(size.width * 0.16, size.height * 0.20)
      ..lineTo(size.width * 0.86, size.height * 0.50)
      ..lineTo(size.width * 0.16, size.height * 0.80)
      ..lineTo(size.width * 0.30, size.height * 0.54)
      ..lineTo(size.width * 0.86, size.height * 0.50)
      ..lineTo(size.width * 0.30, size.height * 0.46)
      ..close();
    canvas.drawPath(path, stroke);
  }

  void _mic(Canvas canvas, Size size, Paint stroke) {
    final body = Rect.fromLTWH(
      size.width * 0.38,
      size.height * 0.12,
      size.width * 0.24,
      size.height * 0.44,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(size.width * 0.12)),
      stroke,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * 0.26,
        size.height * 0.34,
        size.width * 0.48,
        size.height * 0.34,
      ),
      0,
      3.14,
      false,
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.50, size.height * 0.68),
      Offset(size.width * 0.50, size.height * 0.84),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.36, size.height * 0.84),
      Offset(size.width * 0.64, size.height * 0.84),
      stroke,
    );
  }

  void _slash(Canvas canvas, Size size, Paint stroke) {
    canvas.drawLine(
      Offset(size.width * 0.18, size.height * 0.18),
      Offset(size.width * 0.82, size.height * 0.82),
      stroke,
    );
  }

  void _emoji(Canvas canvas, Size size, Paint stroke) {
    canvas.drawCircle(size.center(Offset.zero), size.width * 0.38, stroke);
    canvas.drawCircle(
      Offset(size.width * 0.38, size.height * 0.42),
      size.width * 0.035,
      stroke,
    );
    canvas.drawCircle(
      Offset(size.width * 0.62, size.height * 0.42),
      size.width * 0.035,
      stroke,
    );
    final mouth = Path()
      ..moveTo(size.width * 0.35, size.height * 0.60)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.72,
        size.width * 0.65,
        size.height * 0.60,
      );
    canvas.drawPath(mouth, stroke);
  }

  void _sticker(Canvas canvas, Size size, Paint stroke) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.18,
        size.height * 0.14,
        size.width * 0.64,
        size.height * 0.72,
      ),
      Radius.circular(size.width * 0.12),
    );
    canvas.drawRRect(rect, stroke);
    final fold = Path()
      ..moveTo(size.width * 0.58, size.height * 0.86)
      ..quadraticBezierTo(
        size.width * 0.80,
        size.height * 0.78,
        size.width * 0.82,
        size.height * 0.56,
      );
    canvas.drawPath(fold, stroke);
  }

  void _settings(Canvas canvas, Size size, Paint stroke) {
    final center = Offset(size.width * 0.50, size.height * 0.50);
    canvas.drawCircle(center, size.width * 0.13, stroke);
    canvas.drawCircle(center, size.width * 0.26, stroke);
    for (final angle in [0.0, 1.05, 2.10, 3.14, 4.19, 5.24]) {
      final inner = Offset(
        center.dx + size.width * 0.29 * math.cos(angle),
        center.dy + size.width * 0.29 * math.sin(angle),
      );
      final outer = Offset(
        center.dx + size.width * 0.40 * math.cos(angle),
        center.dy + size.width * 0.40 * math.sin(angle),
      );
      canvas.drawLine(inner, outer, stroke);
    }
  }

  void _call(Canvas canvas, Size size, Paint stroke) {
    final path = Path()
      ..moveTo(size.width * 0.28, size.height * 0.18)
      ..cubicTo(
        size.width * 0.16,
        size.height * 0.28,
        size.width * 0.20,
        size.height * 0.50,
        size.width * 0.36,
        size.height * 0.66,
      )
      ..cubicTo(
        size.width * 0.52,
        size.height * 0.82,
        size.width * 0.74,
        size.height * 0.86,
        size.width * 0.84,
        size.height * 0.74,
      )
      ..lineTo(size.width * 0.70, size.height * 0.58)
      ..lineTo(size.width * 0.56, size.height * 0.66)
      ..lineTo(size.width * 0.36, size.height * 0.46)
      ..lineTo(size.width * 0.44, size.height * 0.32)
      ..close();
    canvas.drawPath(path, stroke);
  }

  void _video(Canvas canvas, Size size, Paint stroke) {
    final rect = Rect.fromLTWH(
      size.width * 0.14,
      size.height * 0.28,
      size.width * 0.50,
      size.height * 0.44,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.08)),
      stroke,
    );
    final lens = Path()
      ..moveTo(size.width * 0.64, size.height * 0.44)
      ..lineTo(size.width * 0.86, size.height * 0.32)
      ..lineTo(size.width * 0.86, size.height * 0.68)
      ..lineTo(size.width * 0.64, size.height * 0.56)
      ..close();
    canvas.drawPath(lens, stroke);
  }

  void _search(Canvas canvas, Size size, Paint stroke) {
    canvas.drawCircle(
      Offset(size.width * 0.43, size.height * 0.43),
      size.width * 0.22,
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.60, size.height * 0.60),
      Offset(size.width * 0.82, size.height * 0.82),
      stroke,
    );
  }

  void _more(Canvas canvas, Size size, Paint fill) {
    for (final x in [0.30, 0.50, 0.70]) {
      canvas.drawCircle(
        Offset(size.width * x, size.height * 0.50),
        size.width * 0.055,
        fill,
      );
    }
  }

  void _back(Canvas canvas, Size size, Paint stroke) {
    canvas.drawLine(
      Offset(size.width * 0.24, size.height * 0.50),
      Offset(size.width * 0.82, size.height * 0.50),
      stroke,
    );
    final path = Path()
      ..moveTo(size.width * 0.42, size.height * 0.26)
      ..lineTo(size.width * 0.18, size.height * 0.50)
      ..lineTo(size.width * 0.42, size.height * 0.74);
    canvas.drawPath(path, stroke);
  }

  void _close(Canvas canvas, Size size, Paint stroke) {
    canvas.drawLine(
      Offset(size.width * 0.26, size.height * 0.26),
      Offset(size.width * 0.74, size.height * 0.74),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.74, size.height * 0.26),
      Offset(size.width * 0.26, size.height * 0.74),
      stroke,
    );
  }

  void _chevronRight(Canvas canvas, Size size, Paint stroke) {
    final path = Path()
      ..moveTo(size.width * 0.38, size.height * 0.24)
      ..lineTo(size.width * 0.62, size.height * 0.50)
      ..lineTo(size.width * 0.38, size.height * 0.76);
    canvas.drawPath(path, stroke);
  }

  void _link(Canvas canvas, Size size, Paint stroke) {
    final left = Rect.fromLTWH(
      size.width * 0.14,
      size.height * 0.36,
      size.width * 0.40,
      size.height * 0.28,
    );
    final right = Rect.fromLTWH(
      size.width * 0.46,
      size.height * 0.36,
      size.width * 0.40,
      size.height * 0.28,
    );
    canvas.save();
    canvas.translate(size.width * 0.02, 0);
    canvas.rotate(-0.50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(left, Radius.circular(size.width * 0.14)),
      stroke,
    );
    canvas.restore();
    canvas.save();
    canvas.translate(-size.width * 0.02, size.height * 0.26);
    canvas.rotate(-0.50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(right, Radius.circular(size.width * 0.14)),
      stroke,
    );
    canvas.restore();
  }

  void _camera(Canvas canvas, Size size, Paint stroke) {
    final body = Rect.fromLTWH(
      size.width * 0.14,
      size.height * 0.30,
      size.width * 0.72,
      size.height * 0.46,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(size.width * 0.10)),
      stroke,
    );
    final cap = Rect.fromLTWH(
      size.width * 0.30,
      size.height * 0.20,
      size.width * 0.24,
      size.height * 0.12,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(cap, Radius.circular(size.width * 0.04)),
      stroke,
    );
    canvas.drawCircle(
      Offset(size.width * 0.52, size.height * 0.53),
      size.width * 0.14,
      stroke,
    );
    canvas.drawCircle(
      Offset(size.width * 0.74, size.height * 0.40),
      size.width * 0.025,
      stroke,
    );
  }

  void _image(Canvas canvas, Size size, Paint stroke) {
    final rect = Rect.fromLTWH(
      size.width * 0.14,
      size.height * 0.18,
      size.width * 0.72,
      size.height * 0.64,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.08)),
      stroke,
    );
    canvas.drawCircle(
      Offset(size.width * 0.64, size.height * 0.36),
      size.width * 0.055,
      stroke,
    );
    final mountain = Path()
      ..moveTo(size.width * 0.20, size.height * 0.72)
      ..lineTo(size.width * 0.42, size.height * 0.48)
      ..lineTo(size.width * 0.56, size.height * 0.62)
      ..lineTo(size.width * 0.66, size.height * 0.52)
      ..lineTo(size.width * 0.82, size.height * 0.72);
    canvas.drawPath(mountain, stroke);
  }

  void _location(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final pin = Path()
      ..moveTo(size.width * 0.50, size.height * 0.88)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.62,
        size.width * 0.20,
        size.height * 0.48,
        size.width * 0.20,
        size.height * 0.34,
      )
      ..cubicTo(
        size.width * 0.20,
        size.height * 0.16,
        size.width * 0.34,
        size.height * 0.08,
        size.width * 0.50,
        size.height * 0.08,
      )
      ..cubicTo(
        size.width * 0.66,
        size.height * 0.08,
        size.width * 0.80,
        size.height * 0.16,
        size.width * 0.80,
        size.height * 0.34,
      )
      ..cubicTo(
        size.width * 0.80,
        size.height * 0.48,
        size.width * 0.72,
        size.height * 0.62,
        size.width * 0.50,
        size.height * 0.88,
      )
      ..close();
    canvas.drawPath(pin, stroke);
    canvas.drawCircle(
      Offset(size.width * 0.50, size.height * 0.34),
      size.width * 0.055,
      fill,
    );
  }

  void _poll(Canvas canvas, Size size, Paint stroke) {
    final xs = [0.30, 0.50, 0.70];
    final heights = [0.30, 0.50, 0.40];
    for (var i = 0; i < xs.length; i++) {
      final rect = Rect.fromLTWH(
        size.width * (xs[i] - 0.055),
        size.height * (0.76 - heights[i]),
        size.width * 0.11,
        size.height * heights[i],
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.035)),
        stroke,
      );
    }
    canvas.drawLine(
      Offset(size.width * 0.18, size.height * 0.82),
      Offset(size.width * 0.82, size.height * 0.82),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _PMSymbolPainter oldDelegate) {
    return oldDelegate.symbol != symbol || oldDelegate.color != color;
  }
}
