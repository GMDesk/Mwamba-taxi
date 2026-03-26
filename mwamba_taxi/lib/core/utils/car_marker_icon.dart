import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Generates a minimalist, flat-design, top-view car [BitmapDescriptor].
///
/// No background circle — just the car with a soft drop shadow.
/// The car points UP by default; pass [heading] in degrees (0=north, 90=east)
/// to rotate it to the driver's actual direction.
///
/// Colors:
///   - Body:  #D97706 (amber)  with front slightly darker for direction cue
///   - Shadow: soft black blur underneath for floating effect
///   - Glass:  light blue with white reflection
///   - Wheels: dark slate
Future<BitmapDescriptor> createCarMarkerIcon({
  double size = 120,
  double heading = 0,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
  final center = size / 2;

  // Rotate entire canvas around center by heading
  canvas.save();
  canvas.translate(center, center);
  canvas.rotate(heading * math.pi / 180);
  canvas.translate(-center, -center);

  // ── Soft drop shadow (floating effect) ──
  final shadowPaint = Paint()
    ..color = const Color(0x30000000) // ~19% black
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
  final shadowPath = _carBodyPath(center, center, size, inset: -1);
  canvas.save();
  canvas.translate(0, size * 0.035); // shadow offset down
  canvas.drawPath(shadowPath, shadowPaint);
  canvas.restore();

  // ── Car body ──
  final bodyGrad = Paint()
    ..shader = ui.Gradient.linear(
      Offset(center - size * 0.14, 0),
      Offset(center + size * 0.14, 0),
      [
        const Color(0xFF92400E), // dark edge
        const Color(0xFFD97706), // main amber
        const Color(0xFFF59E0B), // highlight
        const Color(0xFFD97706),
        const Color(0xFF92400E),
      ],
      [0.0, 0.15, 0.5, 0.85, 1.0],
    );
  final bodyPath = _carBodyPath(center, center, size);
  canvas.drawPath(bodyPath, bodyGrad);

  // ── Front hood (darker = direction indicator) ──
  final hoodPaint = Paint()..color = const Color(0xFFB45309).withAlpha(130);
  final carW = size * 0.30;
  final carH = size * 0.62;
  final hoodPath = Path()
    ..moveTo(center - carW * 0.40, center - carH * 0.42)
    ..quadraticBezierTo(center, center - carH * 0.48, center + carW * 0.40, center - carH * 0.42)
    ..lineTo(center + carW * 0.34, center - carH * 0.32)
    ..quadraticBezierTo(center, center - carH * 0.36, center - carW * 0.34, center - carH * 0.32)
    ..close();
  canvas.drawPath(hoodPath, hoodPaint);

  // ── Front windshield ──
  final glassPaint = Paint()
    ..shader = ui.Gradient.linear(
      Offset(center, center - carH * 0.30),
      Offset(center, center - carH * 0.16),
      [const Color(0xFFDBEAFE), const Color(0xFF93C5FD)],
    );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(center - carW * 0.34, center - carH * 0.30, carW * 0.68, carH * 0.16),
      const Radius.circular(3),
    ),
    glassPaint,
  );
  // Glass reflection line
  final reflectPaint = Paint()
    ..color = const Color(0xBBFFFFFF) // ~73% white
    ..strokeWidth = 0.6
    ..style = PaintingStyle.stroke;
  canvas.drawLine(
    Offset(center - carW * 0.18, center - carH * 0.28),
    Offset(center - carW * 0.08, center - carH * 0.19),
    reflectPaint,
  );

  // ── Roof panel ──
  final roofPaint = Paint()
    ..shader = ui.Gradient.radial(
      Offset(center, center - carH * 0.02),
      carW * 0.35,
      [const Color(0xFFFDE68A), const Color(0xFFF59E0B)],
    );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(center - carW * 0.30, center - carH * 0.12, carW * 0.60, carH * 0.22),
      const Radius.circular(3),
    ),
    roofPaint,
  );

  // ── Rear windshield ──
  final rearGlass = Paint()
    ..shader = ui.Gradient.linear(
      Offset(center, center + carH * 0.12),
      Offset(center, center + carH * 0.24),
      [const Color(0xFFDBEAFE), const Color(0xFF93C5FD)],
    );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(center - carW * 0.28, center + carH * 0.12, carW * 0.56, carH * 0.13),
      const Radius.circular(3),
    ),
    rearGlass,
  );

  // ── Headlights (warm yellow) ──
  final lightPaint = Paint()..color = const Color(0xFFFDE68A);
  for (final dx in [-1.0, 1.0]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center + carW * 0.24 * dx, center - carH * 0.45),
          width: carW * 0.22,
          height: carH * 0.03,
        ),
        const Radius.circular(1.5),
      ),
      lightPaint,
    );
  }

  // ── Taillights (red) ──
  final tailPaint = Paint()..color = const Color(0xFFEF4444);
  for (final dx in [-1.0, 1.0]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center + carW * 0.24 * dx, center + carH * 0.44),
          width: carW * 0.22,
          height: carH * 0.03,
        ),
        const Radius.circular(1.5),
      ),
      tailPaint,
    );
  }

  // ── Wheels (dark, rounded) ──
  final wheelPaint = Paint()..color = const Color(0xFF1E293B);
  final rimPaint = Paint()..color = const Color(0xFF94A3B8);
  final ww = carW * 0.18;
  final wh = carH * 0.11;

  for (final fy in [-0.28, 0.18]) {
    for (final fx in [-0.58, 0.58]) {
      final wx = center + carW * fx - (fx < 0 ? ww * 0.3 : -ww * 0.3);
      final wy = center + carH * fy;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(wx, wy, ww, wh),
          Radius.circular(ww / 2),
        ),
        wheelPaint,
      );
      // Rim accent
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(wx + ww * 0.2, wy + wh * 0.2, ww * 0.6, wh * 0.6),
          Radius.circular(ww / 2),
        ),
        rimPaint,
      );
    }
  }

  // ── Side mirrors ──
  final mirrorPaint = Paint()..color = const Color(0xFFD97706);
  for (final dx in [-1.0, 1.0]) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center + carW * 0.52 * dx, center - carH * 0.20),
        width: 5,
        height: 4,
      ),
      mirrorPaint,
    );
  }

  // ── Center shine line (subtle) ──
  final shinePaint = Paint()
    ..color = const Color(0x33FDE68A) // ~20% gold
    ..strokeWidth = 0.5;
  canvas.drawLine(
    Offset(center, center - carH * 0.42),
    Offset(center, center + carH * 0.42),
    shinePaint,
  );

  // ── Small direction arrow at front (subtle) ──
  final arrowPaint = Paint()
    ..color = const Color(0xCCD97706) // ~80% amber
    ..style = PaintingStyle.fill;
  final arrowY = center - carH * 0.50 - 3;
  final arrowPath = Path()
    ..moveTo(center, arrowY - 4)
    ..lineTo(center - 4, arrowY + 2)
    ..lineTo(center, arrowY)
    ..lineTo(center + 4, arrowY + 2)
    ..close();
  canvas.drawPath(arrowPath, arrowPaint);

  canvas.restore(); // end rotation

  final picture = recorder.endRecording();
  final img = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();

  if (byteData != null) {
    return BitmapDescriptor.bytes(byteData.buffer.asUint8List());
  }
  return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
}

/// Builds the main car body outline path (top-view sedan, pointing up).
Path _carBodyPath(double cx, double cy, double size, {double inset = 0}) {
  final carW = size * 0.30 + inset;
  final carH = size * 0.62 + inset;

  return Path()
    // Front (nose – rounded)
    ..moveTo(cx - carW * 0.44, cy - carH * 0.38)
    ..quadraticBezierTo(cx - carW * 0.52, cy - carH * 0.46, cx, cy - carH * 0.50)
    ..quadraticBezierTo(cx + carW * 0.52, cy - carH * 0.46, cx + carW * 0.44, cy - carH * 0.38)
    // Right side
    ..lineTo(cx + carW * 0.50, cy + carH * 0.38)
    // Rear (rounded)
    ..quadraticBezierTo(cx + carW * 0.50, cy + carH * 0.46, cx, cy + carH * 0.50)
    ..quadraticBezierTo(cx - carW * 0.50, cy + carH * 0.46, cx - carW * 0.50, cy + carH * 0.38)
    // Left side back to front
    ..close();
}
