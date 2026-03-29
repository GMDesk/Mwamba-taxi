import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Returns the appropriate car icon pixel size for a given map [zoom] level
/// so the car appears proportional to the road width.
double carSizeForZoom(double zoom) {
  if (zoom >= 19) return 100;
  if (zoom >= 18) return 84;
  if (zoom >= 17) return 68;
  if (zoom >= 16) return 56;
  if (zoom >= 15) return 44;
  if (zoom >= 14) return 36;
  if (zoom >= 13) return 30;
  return 24;
}

/// Returns the polyline pixel width that visually matches the road at [zoom].
int polylineWidthForZoom(double zoom) {
  if (zoom >= 19) return 18;
  if (zoom >= 18) return 14;
  if (zoom >= 17) return 10;
  if (zoom >= 16) return 7;
  if (zoom >= 15) return 5;
  if (zoom >= 14) return 4;
  if (zoom >= 13) return 3;
  return 2;
}

/// Generates a photorealistic top-view dark sedan [BitmapDescriptor].
///
/// Renders a dark metallic car with 3-D shading, tinted glass, chrome trim,
/// LED headlights / taillights, door seams, and matching side mirrors.
/// Points UP by default; pass [heading] (degrees, 0 = north) to rotate.
Future<BitmapDescriptor> createCarMarkerIcon({
  double size = 56,
  double heading = 0,
}) async {
  // Render at 2× so details stay sharp on high-DPI screens
  final s = size * 2;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, s, s));
  final c = s / 2;

  canvas.save();
  canvas.translate(c, c);
  canvas.rotate(heading * math.pi / 180);
  canvas.translate(-c, -c);

  // Proportions – elongated sedan
  final bw = s * 0.32; // body half-width
  final bh = s * 0.70; // body half-height

  // ── Ground shadow ──
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(c, c + s * 0.02), width: bw * 2.1, height: bh * 1.88),
      Radius.circular(bw * 0.55),
    ),
    Paint()
      ..color = const Color(0x50000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.06),
  );

  // ── Main body path ──
  final body = _sedanBody(c, c, bw, bh);

  // Dark metallic base
  canvas.drawPath(
    body,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(c - bw, c),
        Offset(c + bw, c),
        const [
          Color(0xFF0F0F1A),
          Color(0xFF1E1E32),
          Color(0xFF33334D),
          Color(0xFF1E1E32),
          Color(0xFF0F0F1A),
        ],
        [0.0, 0.22, 0.50, 0.78, 1.0],
      ),
  );

  // Top-light reflection (sun overhead)
  canvas.drawPath(
    body,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(c, c - bh),
        Offset(c, c + bh),
        const [
          Color(0x20FFFFFF),
          Color(0x0AFFFFFF),
          Color(0x00000000),
          Color(0x08FFFFFF),
        ],
        [0.0, 0.30, 0.65, 1.0],
      ),
  );

  // ── Hood panel (darker front) ──
  final hoodPath = Path()
    ..moveTo(c - bw * 0.72, c - bh * 0.56)
    ..quadraticBezierTo(c, c - bh * 0.62, c + bw * 0.72, c - bh * 0.56)
    ..lineTo(c + bw * 0.66, c - bh * 0.34)
    ..quadraticBezierTo(c, c - bh * 0.38, c - bw * 0.66, c - bh * 0.34)
    ..close();
  canvas.drawPath(
    hoodPath,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(c, c - bh * 0.62),
        Offset(c, c - bh * 0.34),
        const [Color(0x30000000), Color(0x10000000)],
      ),
  );

  // ── Front windshield ──
  _drawGlass(canvas, c, c - bh * 0.32, bw * 0.62, bh * 0.14, bw * 0.08);

  // ── Rear windshield ──
  _drawGlass(canvas, c, c + bh * 0.20, bw * 0.54, bh * 0.11, bw * 0.06);

  // ── Roof (slightly lighter, with reflection) ──
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(c, c - bh * 0.06), width: bw * 1.10, height: bh * 0.34),
      Radius.circular(bw * 0.12),
    ),
    Paint()
      ..shader = ui.Gradient.radial(
        Offset(c - bw * 0.15, c - bh * 0.12),
        bw * 0.7,
        const [Color(0xFF3A3A56), Color(0xFF22223A)],
      ),
  );

  // ── Roof shine (specular highlight) ──
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(c - bw * 0.12, c - bh * 0.10), width: bw * 0.50, height: bh * 0.10),
      Radius.circular(bw * 0.25),
    ),
    Paint()..color = const Color(0x18FFFFFF),
  );

  // ── Headlights (LED white) ──
  for (final dx in [-1.0, 1.0]) {
    final hx = c + bw * 0.52 * dx;
    final hy = c - bh * 0.58;
    // Glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(hx, hy), width: bw * 0.40, height: bh * 0.06),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(hx, hy),
          bw * 0.20,
          const [Color(0xCCFFFFFF), Color(0x00FFFFFF)],
        ),
    );
    // Core
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(hx, hy), width: bw * 0.26, height: bh * 0.032),
        Radius.circular(bh * 0.016),
      ),
      Paint()..color = const Color(0xFFF0F4FF),
    );
  }

  // ── Taillights (LED red) ──
  for (final dx in [-1.0, 1.0]) {
    final tx = c + bw * 0.50 * dx;
    final ty = c + bh * 0.57;
    // Glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(tx, ty), width: bw * 0.36, height: bh * 0.05),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(tx, ty),
          bw * 0.18,
          const [Color(0xCCFF1A1A), Color(0x00FF1A1A)],
        ),
    );
    // Core
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(tx, ty), width: bw * 0.24, height: bh * 0.028),
        Radius.circular(bh * 0.014),
      ),
      Paint()..color = const Color(0xFFEE2020),
    );
  }

  // ── Wheels (rubber + alloy rim) ──
  for (final fy in [-0.34, 0.28]) {
    for (final fx in [-1.0, 1.0]) {
      _drawWheel(canvas, c + bw * 0.92 * fx, c + bh * fy, bw * 0.18, bh * 0.10);
    }
  }

  // ── Side mirrors (chrome capsule) ──
  for (final dx in [-1.0, 1.0]) {
    final mx = c + bw * 0.96 * dx;
    final my = c - bh * 0.26;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(mx, my), width: bw * 0.16, height: bh * 0.05),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(mx - bw * 0.06, my),
          Offset(mx + bw * 0.06, my),
          const [Color(0xFF666680), Color(0xFFAAAABB), Color(0xFF666680)],
          [0.0, 0.5, 1.0],
        ),
    );
  }

  // ── Door seam lines ──
  final seamPaint = Paint()
    ..color = const Color(0x16000000)
    ..strokeWidth = s * 0.004
    ..style = PaintingStyle.stroke;
  for (final dx in [-1.0, 1.0]) {
    canvas.drawLine(
      Offset(c + bw * 0.82 * dx, c - bh * 0.15),
      Offset(c + bw * 0.82 * dx, c + bh * 0.18),
      seamPaint,
    );
  }

  // ── Center ridge (subtle specular) ──
  canvas.drawLine(
    Offset(c, c - bh * 0.54),
    Offset(c, c + bh * 0.54),
    Paint()
      ..color = const Color(0x0CFFFFFF)
      ..strokeWidth = s * 0.005,
  );

  canvas.restore();

  final picture = recorder.endRecording();
  final img = await picture.toImage(s.toInt(), s.toInt());
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();

  if (byteData != null) {
    return BitmapDescriptor.bytes(
      byteData.buffer.asUint8List(),
      imagePixelRatio: 2.0,
    );
  }
  return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
}

// ─── Private helpers ───────────────────────────────────────────────

/// Smooth sedan body outline (top-view, pointing up).
Path _sedanBody(double cx, double cy, double hw, double hh) {
  return Path()
    // Front bumper
    ..moveTo(cx - hw * 0.60, cy - hh * 0.48)
    ..cubicTo(cx - hw * 0.65, cy - hh * 0.58, cx - hw * 0.30, cy - hh * 0.64, cx, cy - hh * 0.66)
    ..cubicTo(cx + hw * 0.30, cy - hh * 0.64, cx + hw * 0.65, cy - hh * 0.58, cx + hw * 0.60, cy - hh * 0.48)
    // Right side (slight outward curve for fenders)
    ..cubicTo(cx + hw * 0.88, cy - hh * 0.38, cx + hw * 0.92, cy - hh * 0.10, cx + hw * 0.90, cy + hh * 0.10)
    ..cubicTo(cx + hw * 0.92, cy + hh * 0.30, cx + hw * 0.88, cy + hh * 0.42, cx + hw * 0.60, cy + hh * 0.50)
    // Rear bumper
    ..cubicTo(cx + hw * 0.30, cy + hh * 0.60, cx + hw * 0.15, cy + hh * 0.62, cx, cy + hh * 0.62)
    ..cubicTo(cx - hw * 0.15, cy + hh * 0.62, cx - hw * 0.30, cy + hh * 0.60, cx - hw * 0.60, cy + hh * 0.50)
    // Left side
    ..cubicTo(cx - hw * 0.88, cy + hh * 0.42, cx - hw * 0.92, cy + hh * 0.30, cx - hw * 0.90, cy + hh * 0.10)
    ..cubicTo(cx - hw * 0.92, cy - hh * 0.10, cx - hw * 0.88, cy - hh * 0.38, cx - hw * 0.60, cy - hh * 0.48)
    ..close();
}

/// Tinted glass panel with specular reflection.
void _drawGlass(Canvas canvas, double cx, double cy, double hw, double hh, double r) {
  final rrect = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset(cx, cy), width: hw * 2, height: hh * 2),
    Radius.circular(r),
  );
  // Dark tinted glass
  canvas.drawRRect(
    rrect,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx, cy - hh),
        Offset(cx, cy + hh),
        const [Color(0xFF2A3A50), Color(0xFF1A2636)],
      ),
  );
  // Reflection highlight
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx - hw * 0.25, cy - hh * 0.30), width: hw * 0.60, height: hh * 0.40),
      Radius.circular(r * 0.5),
    ),
    Paint()..color = const Color(0x20FFFFFF),
  );
}

/// Realistic wheel: dark tire + lighter alloy rim.
void _drawWheel(Canvas canvas, double cx, double cy, double hw, double hh) {
  // Tire (dark rubber)
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: hw * 2, height: hh * 2),
      Radius.circular(hw * 0.4),
    ),
    Paint()..color = const Color(0xFF111118),
  );
  // Alloy rim (chrome / silver)
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: hw * 1.3, height: hh * 1.3),
      Radius.circular(hw * 0.35),
    ),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx - hw * 0.3, cy),
        Offset(cx + hw * 0.3, cy),
        const [Color(0xFF555566), Color(0xFF999AAA), Color(0xFF555566)],
        [0.0, 0.5, 1.0],
      ),
  );
}
