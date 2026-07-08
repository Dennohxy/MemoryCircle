import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Code-drawn scrapbook decorations, recreated from the torn-paper collage
/// template artwork: pastel paper patches with torn white fringes, gold
/// sprinkles, leafy sprigs, stylized blossoms, washi tape, and white-framed
/// photo prints.
///
/// Everything is vector-drawn so pages stay crisp and adaptive at any size,
/// and every page uses a deterministic seed so it always looks the same on
/// every device.

/// One scrapbook color story (paper patch colors, metallic accent, flower).
class ScrapbookPalette {
  const ScrapbookPalette({
    required this.papers,
    required this.accent,
    required this.blossom,
  });

  /// Torn-paper patch colors, layered back to front.
  final List<Color> papers;

  /// Metallic accent for sprinkles, sprigs, and tape.
  final Color accent;

  /// Stylized flower color.
  final Color blossom;
}

/// Palettes sampled from the template artwork.
const List<ScrapbookPalette> scrapbookPalettes = [
  // Blush, navy and gold.
  ScrapbookPalette(
    papers: [
      Color(0xFFEFC3BC),
      Color(0xFF32415C),
      Color(0xFFF8E9DF),
      Color(0xFF9FBFBB),
    ],
    accent: Color(0xFFC9A227),
    blossom: Color(0xFFEFB7B0),
  ),
  // Teal and peach.
  ScrapbookPalette(
    papers: [
      Color(0xFF9CC3BB),
      Color(0xFFF3B69E),
      Color(0xFFF7E7D3),
      Color(0xFF6E9E96),
    ],
    accent: Color(0xFFC9A227),
    blossom: Color(0xFFF08E7D),
  ),
  // Sage, cream and rose.
  ScrapbookPalette(
    papers: [
      Color(0xFFB9C4A9),
      Color(0xFFF4DFD3),
      Color(0xFFE5EBDD),
      Color(0xFFD98E8A),
    ],
    accent: Color(0xFFB98B3A),
    blossom: Color(0xFFE0A0A5),
  ),
  // Dusty blue and sand.
  ScrapbookPalette(
    papers: [
      Color(0xFFA9BFCF),
      Color(0xFFEBD8BE),
      Color(0xFFF4EDE1),
      Color(0xFF748CA5),
    ],
    accent: Color(0xFFC9A227),
    blossom: Color(0xFFE8B9A5),
  ),
];

ScrapbookPalette scrapbookPaletteFor(int seed) =>
    scrapbookPalettes[seed.abs() % scrapbookPalettes.length];

/// Paints torn-paper corner collages, gold sprinkles, a leafy sprig, and an
/// occasional blossom around the edges of an album page. Content is drawn on
/// top, so the collage frames it without getting in the way.
class ScrapbookDecorPainter extends CustomPainter {
  ScrapbookDecorPainter({
    required this.seed,
    required this.palette,
    this.dense = false,
  });

  final int seed;
  final ScrapbookPalette palette;

  /// Title pages get a fuller collage on all corners.
  final bool dense;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    const corners = <Alignment>[
      Alignment.topLeft,
      Alignment.topRight,
      Alignment.bottomRight,
      Alignment.bottomLeft,
    ];
    final decorated = <Alignment>[
      for (final corner in corners)
        if (dense || random.nextDouble() < 0.72) corner,
    ];
    if (decorated.isEmpty) decorated.add(corners[random.nextInt(4)]);

    var colorShift = random.nextInt(palette.papers.length);
    for (final corner in decorated) {
      _paintCornerCollage(canvas, size, corner, random, colorShift);
      colorShift++;
    }
    for (final corner in decorated) {
      _paintSprinkles(canvas, size, corner, random);
    }
    _paintSprig(canvas, size, decorated.first, random);
    if (dense && decorated.length > 1) {
      _paintSprig(canvas, size, decorated.last, random);
    }
    if (dense || random.nextDouble() < 0.45) {
      _paintBlossom(
          canvas, size, decorated[random.nextInt(decorated.length)], random);
    }
  }

  Offset _cornerPoint(Size size, Alignment corner) => Offset(
        corner.x < 0 ? 0 : size.width,
        corner.y < 0 ? 0 : size.height,
      );

  void _paintCornerCollage(Canvas canvas, Size size, Alignment corner,
      math.Random random, int colorShift) {
    final origin = _cornerPoint(size, corner);
    final dx = corner.x < 0 ? 1.0 : -1.0;
    final dy = corner.y < 0 ? 1.0 : -1.0;
    final boost = dense ? 1.15 : 1.0;
    final layers = dense ? 3 : 2 + random.nextInt(2);
    for (var layer = 0; layer < layers; layer++) {
      final shrink = math.pow(0.78, layer).toDouble() * boost;
      final alongX = size.width * (0.20 + random.nextDouble() * 0.13) * shrink;
      final alongY = size.height * (0.22 + random.nextDouble() * 0.15) * shrink;
      final patch = _tornPatch(origin, dx, dy, alongX, alongY, random);
      // The white torn fringe peeks out from under the colored paper.
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.scale(1.05);
      canvas.translate(-origin.dx, -origin.dy);
      canvas.drawPath(
          patch, Paint()..color = Colors.white.withValues(alpha: 0.9));
      canvas.restore();
      final color =
          palette.papers[(colorShift + layer) % palette.papers.length];
      canvas.drawPath(patch, Paint()..color = color.withValues(alpha: 0.92));
    }
  }

  Path _tornPatch(Offset corner, double dx, double dy, double alongX,
      double alongY, math.Random random) {
    final path = Path()
      ..moveTo(corner.dx, corner.dy)
      ..lineTo(corner.dx + dx * alongX, corner.dy);
    const steps = 8;
    final jitter = 0.05 * (alongX + alongY) / 2;
    for (var i = 1; i <= steps; i++) {
      final angle = (i / (steps + 1)) * math.pi / 2;
      final x = corner.dx +
          dx * alongX * math.cos(angle) +
          (random.nextDouble() - 0.5) * 2 * jitter;
      final y = corner.dy +
          dy * alongY * math.sin(angle) +
          (random.nextDouble() - 0.5) * 2 * jitter;
      path.lineTo(x, y);
    }
    path
      ..lineTo(corner.dx, corner.dy + dy * alongY)
      ..close();
    return path;
  }

  void _paintSprinkles(
      Canvas canvas, Size size, Alignment corner, math.Random random) {
    final origin = _cornerPoint(size, corner);
    final dx = corner.x < 0 ? 1.0 : -1.0;
    final dy = corner.y < 0 ? 1.0 : -1.0;
    final count = dense ? 10 : 6;
    final paint = Paint()..color = palette.accent.withValues(alpha: 0.8);
    for (var i = 0; i < count; i++) {
      final x = origin.dx + dx * random.nextDouble() * size.width * 0.30;
      final y = origin.dy + dy * random.nextDouble() * size.height * 0.32;
      final radius = size.shortestSide * (0.003 + random.nextDouble() * 0.006);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  void _paintSprig(
      Canvas canvas, Size size, Alignment corner, math.Random random) {
    final origin = _cornerPoint(size, corner);
    final dx = corner.x < 0 ? 1.0 : -1.0;
    final dy = corner.y < 0 ? 1.0 : -1.0;
    final start = Offset(
      origin.dx + dx * size.width * 0.05,
      origin.dy + dy * size.height * 0.06,
    );
    final length = size.shortestSide * (0.20 + random.nextDouble() * 0.08);
    final baseAngle = math.atan2(dy, dx) + (random.nextDouble() - 0.5) * 0.5;
    final end =
        start + Offset(math.cos(baseAngle), math.sin(baseAngle)) * length;
    final control = start +
        Offset(math.cos(baseAngle + 0.45), math.sin(baseAngle + 0.45)) *
            (length * 0.55);
    final stroke = Paint()
      ..color = palette.accent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, size.shortestSide * 0.004)
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy),
      stroke,
    );

    Offset pointAt(double t) {
      final u = 1 - t;
      return Offset(
        u * u * start.dx + 2 * u * t * control.dx + t * t * end.dx,
        u * u * start.dy + 2 * u * t * control.dy + t * t * end.dy,
      );
    }

    final leaf = Paint()..color = palette.accent.withValues(alpha: 0.75);
    var side = 1.0;
    for (final t in const [0.3, 0.5, 0.7, 0.9]) {
      final point = pointAt(t);
      final ahead = pointAt(math.min(1, t + 0.05));
      final tangent = math.atan2(ahead.dy - point.dy, ahead.dx - point.dx);
      final leafLength = length * (0.20 - 0.03 * t);
      canvas.save();
      canvas.translate(point.dx, point.dy);
      canvas.rotate(tangent + side * 0.9);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(leafLength * 0.5, 0),
          width: leafLength,
          height: leafLength * 0.42,
        ),
        leaf,
      );
      canvas.restore();
      side = -side;
    }
  }

  void _paintBlossom(
      Canvas canvas, Size size, Alignment corner, math.Random random) {
    final origin = _cornerPoint(size, corner);
    final dx = corner.x < 0 ? 1.0 : -1.0;
    final dy = corner.y < 0 ? 1.0 : -1.0;
    final center = Offset(
      origin.dx + dx * size.width * (0.07 + random.nextDouble() * 0.05),
      origin.dy + dy * size.height * (0.08 + random.nextDouble() * 0.05),
    );
    final radius = size.shortestSide * (dense ? 0.075 : 0.06);
    const petals = 6;
    final spin = random.nextDouble() * math.pi;
    final outer = Paint()..color = palette.blossom;
    for (var i = 0; i < petals; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(spin + i * 2 * math.pi / petals);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(radius * 0.58, 0),
          width: radius * 1.05,
          height: radius * 0.58,
        ),
        outer,
      );
      canvas.restore();
    }
    final inner = Paint()
      ..color = Color.lerp(palette.blossom, Colors.white, 0.4)!;
    for (var i = 0; i < petals; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(spin + (i + 0.5) * 2 * math.pi / petals);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(radius * 0.34, 0),
          width: radius * 0.62,
          height: radius * 0.36,
        ),
        inner,
      );
      canvas.restore();
    }
    canvas.drawCircle(center, radius * 0.16, Paint()..color = palette.accent);
  }

  @override
  bool shouldRepaint(covariant ScrapbookDecorPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.palette != palette ||
      oldDelegate.dense != dense;
}

/// A little strip of translucent washi tape.
class WashiTape extends StatelessWidget {
  const WashiTape({
    super.key,
    this.angle = -0.30,
    this.width = 54,
    this.tint,
  });

  final double angle;
  final double width;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final edge = (tint ?? const Color(0xFFC9A227)).withValues(alpha: 0.30);
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: width,
        height: width * 0.30,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              edge,
              Colors.white.withValues(alpha: 0.55),
              edge,
            ],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// A photo styled as a printed picture: white border, soft shadow, a slight
/// tilt, and a strip of washi tape holding it to the page.
class FramedPhoto extends StatelessWidget {
  const FramedPhoto({
    super.key,
    required this.child,
    this.angle = 0,
    this.taped = true,
    this.tapeTint,
  });

  final Widget child;
  final double angle;
  final bool taped;
  final Color? tapeTint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final framed = Transform.rotate(
          angle: angle,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x2E000000),
                  blurRadius: 9,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(5),
            child: ClipRect(child: child),
          ),
        );
        if (!taped) return framed;
        final tapeWidth =
            math.max(34.0, constraints.maxWidth * 0.24).clamp(34.0, 72.0);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            framed,
            Positioned(
              top: -tapeWidth * 0.12,
              child: WashiTape(
                angle: angle - 0.28,
                width: tapeWidth,
                tint: tapeTint,
              ),
            ),
          ],
        );
      },
    );
  }
}
