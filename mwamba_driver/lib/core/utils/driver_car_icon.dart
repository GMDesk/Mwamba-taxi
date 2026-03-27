import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Generates a top-view car marker with an amber halo for the driver's own position.
/// The car points UP by default; pass [heading] in degrees to rotate.
Future<BitmapDescriptor> createDriverCarIcon({
  double size = 90,
  double heading = 0,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
  final center = size / 2;

  canvas.save();
  canvas.translate(center, center);
  canvas.rotate(heading * math.pi / 180);
  canvas.translate(-center, -center);

  // ── Amber halo (pulse ring) ──
  final haloPaint = Paint()
    ..shader = ui.Gradient.radial(
      Offset(center, center),
      size * 0.48,
      [
        const Color(0x00D97706),
        const Color(0x15D97706),
        const Color(0x30D97706),
        const Color(0x00D97706),
      ],
      [0.0, 0.5, 0.75, 1.0],
    );
  canvas.drawCircle(Offset(center, center), size * 0.48, haloPaint);

  // ── Soft drop shadow ──
  final shadowPaint = Paint()
    ..color = const Color(0x40000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
  final shadowPath = _carBodyPath(center, center, size, inset: -1);
  canvas.save();
  canvas.translate(0, size * 0.03);
  canvas.drawPath(shadowPath, shadowPaint);
  canvas.restore();

  // ── Car body ──
  final bodyGrad = Paint()
    ..shader = ui.Gradient.linear(
      Offset(center - size * 0.14, 0),
      Offset(center + size * 0.14, 0),
      [
        const Color(0xFF92400E),
        const Color(0xFFD97706),
        const Color(0xFFF59E0B),
        const Color(0xFFD97706),
        const Color(0xFF92400E),
      ],
      [0.0, 0.15, 0.5, 0.85, 1.0],
    );
  final bodyPath = _carBodyPath(center, center, size);
  canvas.drawPath(bodyPath, bodyGrad);

  // ── Front hood ──
  final hoodPaint = Paint()..color = const Color(0xFFB45309).withAlpha(130);
  final carW = size * 0.28;
  final carH = size * 0.58;
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

  // ── Headlights ──
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

  // ── Taillights ──
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

  // ── Wheels ──
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

  // ── Direction arrow at front ──
  final arrowPaint = Paint()
    ..color = const Color(0xCCD97706)
    ..style = PaintingStyle.fill;
  final arrowY = center - carH * 0.50 - 3;
  final arrowPath = Path()
    ..moveTo(center, arrowY - 5)
    ..lineTo(center - 5, arrowY + 2)
    ..lineTo(center, arrowY)
    ..lineTo(center + 5, arrowY + 2)
    ..close();
  canvas.drawPath(arrowPath, arrowPaint);

  canvas.restore();

  final picture = recorder.endRecording();
  final img = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();

  if (byteData != null) {
    return BitmapDescriptor.bytes(byteData.buffer.asUint8List());
  }
  return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
}

Path _carBodyPath(double cx, double cy, double size, {double inset = 0}) {
  final carW = size * 0.28 + inset;
  final carH = size * 0.58 + inset;

  return Path()
    ..moveTo(cx - carW * 0.44, cy - carH * 0.38)
    ..quadraticBezierTo(cx - carW * 0.52, cy - carH * 0.46, cx, cy - carH * 0.50)
    ..quadraticBezierTo(cx + carW * 0.52, cy - carH * 0.46, cx + carW * 0.44, cy - carH * 0.38)
    ..lineTo(cx + carW * 0.50, cy + carH * 0.38)
    ..quadraticBezierTo(cx + carW * 0.50, cy + carH * 0.46, cx, cy + carH * 0.50)
    ..quadraticBezierTo(cx - carW * 0.50, cy + carH * 0.46, cx - carW * 0.50, cy + carH * 0.38)
    ..close();
}
