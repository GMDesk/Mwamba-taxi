import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  MWAMBA PREMIUM VEHICLE MARKER
//  White metallic sedan – semi-realistic 3/4 top-down perspective
//  Pure Canvas rendering with realistic wheels, reflections, chrome details.
//  No shadow · No cartoon · Transparent background
// ═════════════════════════════════════════════════════════════════════════════

/// Ride-state driven accent (halo / indicator).  Body is always white.
enum VehicleState { available, enRoute, arrived, inProgress }

/// Returns the appropriate car icon pixel size for a given map [zoom] level.
double carSizeForZoom(double zoom) {
  if (zoom >= 19) return 120;
  if (zoom >= 18) return 96;
  if (zoom >= 17) return 76;
  if (zoom >= 16) return 62;
  if (zoom >= 15) return 50;
  if (zoom >= 14) return 40;
  if (zoom >= 13) return 34;
  return 28;
}

/// Returns polyline pixel width matching road width at [zoom].
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

// ── Accent colours per state (for halo only – body stays white) ──────────
class _Acc {
  final Color primary;
  final Color glow;
  const _Acc(this.primary, this.glow);
}

const _accents = <VehicleState, _Acc>{
  VehicleState.available:  _Acc(Color(0xFF4285F4), Color(0x404285F4)),
  VehicleState.enRoute:    _Acc(Color(0xFF34A853), Color(0x4034A853)),
  VehicleState.arrived:    _Acc(Color(0xFFFFA000), Color(0x40FFA000)),
  VehicleState.inProgress: _Acc(Color(0xFF1A73E8), Color(0x401A73E8)),
};

// ═══════════════════════════════════════════════════════════════════════════
//  SPRITE CACHE  –  16 angles × zoom-bucket × state
// ═══════════════════════════════════════════════════════════════════════════

final Map<String, BitmapDescriptor> _spriteCache = {};
const int _angleSlots = 16;

Future<BitmapDescriptor> getVehicleMarker({
  required double heading,
  double zoom = 14,
  VehicleState state = VehicleState.available,
  bool isDriverSelf = false,
}) async {
  final bucket = zoom.round();
  final slot = ((heading % 360) / (360 / _angleSlots)).round() % _angleSlots;
  final key = '$bucket-${state.index}-$slot${isDriverSelf ? "-d" : ""}';

  if (_spriteCache.containsKey(key)) return _spriteCache[key]!;

  final size = carSizeForZoom(zoom);
  final angle = slot * (360.0 / _angleSlots);
  final bmp = await _renderVehicle(
    size: size,
    heading: angle,
    state: state,
    isDriverSelf: isDriverSelf,
  );
  _spriteCache[key] = bmp;
  return bmp;
}

void clearVehicleCache() => _spriteCache.clear();

// ═══════════════════════════════════════════════════════════════════════════
//  RENDERING ENGINE  –  White metallic sedan, 3/4 top-down perspective
//  Visible wheels, chrome trim, door handles, reflections on white body.
//  NO ground shadow.  Transparent background.
// ═══════════════════════════════════════════════════════════════════════════

Future<BitmapDescriptor> _renderVehicle({
  required double size,
  required double heading,
  required VehicleState state,
  required bool isDriverSelf,
}) async {
  final raw = size * 2.0;        // 2× for retina
  final s = raw < 8 ? 8.0 : raw; // minimum 4×4 logical px
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, Rect.fromLTWH(0, 0, s, s));
  final acc = _accents[state]!;

  // Car proportions (3/4 view: longer than wide)
  final hw = s * 0.30;           // body half-width
  final hh = s * 0.44;          // body half-height (front→back)

  canvas.save();
  canvas.translate(s / 2, s / 2);
  canvas.rotate(heading * math.pi / 180);

  // ── 1. Driver-self accent halo ──
  if (isDriverSelf) {
    canvas.drawCircle(
      Offset.zero,
      s * 0.46,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero, s * 0.46,
          [acc.primary.withOpacity(0.0), acc.primary.withOpacity(0.22), acc.primary.withOpacity(0.0)],
          [0.0, 0.72, 1.0],
        ),
    );
  }

  // ── 2. Wheels (drawn FIRST – body overlaps inner half) ──
  for (final pos in [
    Offset(-hw * 0.78, -hh * 0.50),  // front-left
    Offset( hw * 0.78, -hh * 0.50),  // front-right
    Offset(-hw * 0.76,  hh * 0.46),  // rear-left
    Offset( hw * 0.76,  hh * 0.46),  // rear-right
  ]) {
    _drawWheel(canvas, pos.dx, pos.dy, hw * 0.17, hh * 0.10, s);
  }

  // ── 3. Main body shell (white metallic) ──
  final body = _bodyPath(hw, hh);

  // 3a. Base solid slate-gray (visible on light & dark map tiles)
  canvas.drawPath(body, Paint()..color = const Color(0xFF4A5060));

  // 3b. Side-to-side gradient for 3D volume (darker edges for depth)
  canvas.drawPath(body, Paint()
    ..shader = ui.Gradient.linear(
      Offset(-hw, 0), Offset(hw, 0),
      [const Color(0x30000000), const Color(0x00000000), const Color(0x10FFFFFF), const Color(0x00000000), const Color(0x28000000)],
      [0.0, 0.22, 0.46, 0.74, 1.0],
    ));

  // 3c. Front-to-back gradient (lit from front)
  canvas.drawPath(body, Paint()
    ..shader = ui.Gradient.linear(
      Offset(0, -hh), Offset(0, hh),
      [const Color(0x18FFFFFF), const Color(0x08FFFFFF), const Color(0x00000000), const Color(0x14000000)],
      [0.0, 0.30, 0.60, 1.0],
    ));

  // 3d. Metallic specular patch (upper-left)
  canvas.drawPath(body, Paint()
    ..shader = ui.Gradient.radial(
      Offset(-hw * 0.25, -hh * 0.20), hw * 1.1,
      [const Color(0x12FFFFFF), const Color(0x00FFFFFF)],
    ));

  // ── 4. Fender arch shadows (over wheel wells) ──
  for (final side in [-1.0, 1.0]) {
    for (final fb in [-0.50, 0.46]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(hw * 0.72 * side, hh * fb),
          width: hw * 0.40, height: hh * 0.24,
        ),
        Paint()
          ..color = const Color(0x0E000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.010),
      );
    }
  }

  // ── 5. Hood panel (front) ──
  final hoodP = Path()
    ..moveTo(-hw * 0.66, -hh * 0.36)
    ..quadraticBezierTo(0, -hh * 0.40, hw * 0.66, -hh * 0.36)
    ..lineTo(hw * 0.56, -hh * 0.62)
    ..quadraticBezierTo(0, -hh * 0.68, -hw * 0.56, -hh * 0.62)
    ..close();
  canvas.drawPath(hoodP, Paint()
    ..shader = ui.Gradient.linear(
      Offset(0, -hh * 0.68), Offset(0, -hh * 0.36),
      [const Color(0x08000010), const Color(0x00000000)],
    ));
  // Hood centre crease
  canvas.drawLine(
    Offset(0, -hh * 0.63), Offset(0, -hh * 0.40),
    Paint()..color = const Color(0x14000020)..strokeWidth = s * 0.004..strokeCap = StrokeCap.round,
  );

  // ── 6. Front grille (thin dark slot) ──
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(0, -hh * 0.75), width: hw * 0.68, height: hh * 0.024),
      Radius.circular(hh * 0.012),
    ),
    Paint()..color = const Color(0xFF333340),
  );

  // ── 7. Trunk panel (rear) ──
  final trunkP = Path()
    ..moveTo(-hw * 0.60, hh * 0.40)
    ..quadraticBezierTo(0, hh * 0.44, hw * 0.60, hh * 0.40)
    ..lineTo(hw * 0.48, hh * 0.62)
    ..quadraticBezierTo(0, hh * 0.68, -hw * 0.48, hh * 0.62)
    ..close();
  canvas.drawPath(trunkP, Paint()..color = const Color(0x0A000008));

  // ── 8. Front windshield (dark tinted glass with reflection) ──
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(0, -hh * 0.20), width: hw * 1.18, height: hh * 0.22),
      Radius.circular(hw * 0.10),
    ),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, -hh * 0.31), Offset(0, -hh * 0.09),
        [const Color(0xFF18232E), const Color(0xFF2C3C4E)],
      ),
  );
  // Reflection streak on windshield
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(-hw * 0.18, -hh * 0.22), width: hw * 0.55, height: hh * 0.035),
      Radius.circular(hw * 0.06),
    ),
    Paint()..color = const Color(0x30FFFFFF),
  );
  // Chrome trim around windshield
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(0, -hh * 0.20), width: hw * 1.22, height: hh * 0.24),
      Radius.circular(hw * 0.11),
    ),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.003
      ..color = const Color(0x30FFFFFF),
  );

  // ── 9. Rear windshield ──
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(0, hh * 0.24), width: hw * 0.96, height: hh * 0.16),
      Radius.circular(hw * 0.08),
    ),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, hh * 0.16), Offset(0, hh * 0.32),
        [const Color(0xFF2C3C4E), const Color(0xFF18232E)],
      ),
  );

  // ── 10. Roof (raised, slightly lighter gray with sky reflection) ──
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(0, -hh * 0.01), width: hw * 0.90, height: hh * 0.30),
      Radius.circular(hw * 0.16),
    ),
    Paint()
      ..shader = ui.Gradient.radial(
        Offset(-hw * 0.10, -hh * 0.06), hw * 0.65,
        [const Color(0xFF687080), const Color(0xFF556068)],
      ),
  );
  // Roof specular highlight
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(-hw * 0.08, -hh * 0.05), width: hw * 0.38, height: hh * 0.08),
      Radius.circular(hw * 0.20),
    ),
    Paint()..color = const Color(0x20FFFFFF),
  );

  // ── 11. Side windows (dark glass strips) ──
  for (final side in [-1.0, 1.0]) {
    final wp = Path()
      ..moveTo(hw * 0.54 * side, -hh * 0.28)
      ..quadraticBezierTo(hw * 0.58 * side, -hh * 0.03, hw * 0.52 * side, hh * 0.20)
      ..lineTo(hw * 0.46 * side, hh * 0.18)
      ..quadraticBezierTo(hw * 0.50 * side, -hh * 0.03, hw * 0.46 * side, -hh * 0.26)
      ..close();
    canvas.drawPath(wp, Paint()..color = const Color(0xCC1A2636));
  }

  // ── 12. Headlights (warm white LED strips) ──
  for (final side in [-1.0, 1.0]) {
    final hx = hw * 0.50 * side;
    final hy = -hh * 0.68;
    // Glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(hx, hy), width: hw * 0.30, height: hh * 0.06),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(hx, hy), hw * 0.16,
          [const Color(0x88FFFFF0), const Color(0x00FFFFF0)],
        ),
    );
    // LED bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(hx, hy), width: hw * 0.22, height: hh * 0.022),
        Radius.circular(hh * 0.011),
      ),
      Paint()..color = const Color(0xFFF8F8F0),
    );
  }

  // ── 13. Taillights (subtle red LED strips) ──
  for (final side in [-1.0, 1.0]) {
    final tx = hw * 0.46 * side;
    final ty = hh * 0.64;
    // Red glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(tx, ty), width: hw * 0.26, height: hh * 0.05),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(tx, ty), hw * 0.14,
          [const Color(0x88FF1818), const Color(0x00FF1818)],
        ),
    );
    // LED bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(tx, ty), width: hw * 0.20, height: hh * 0.020),
        Radius.circular(hh * 0.010),
      ),
      Paint()..color = const Color(0xFFEE2020),
    );
  }

  // ── 14. Side mirrors (body-matched ovals) ──
  for (final side in [-1.0, 1.0]) {
    final mx = hw * 0.98 * side;
    final my = -hh * 0.22;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(mx, my), width: hw * 0.13, height: hh * 0.055),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(mx - hw * 0.05, my), Offset(mx + hw * 0.05, my),
          [const Color(0xFF3A4050), const Color(0xFF606878), const Color(0xFF3A4050)],
          [0.0, 0.5, 1.0],
        ),
    );
  }

  // ── 15. Door handles (tiny chrome rectangles) ──
  for (final side in [-1.0, 1.0]) {
    for (final yf in [-0.08, 0.10]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(hw * 0.72 * side, hh * yf),
            width: hw * 0.08, height: hh * 0.016,
          ),
          Radius.circular(hh * 0.008),
        ),
        Paint()..color = const Color(0xFF8890A0),
      );
    }
  }

  // ── 16. Belt-line chrome trim (cabin perimeter) ──
  final beltP = Path()
    ..moveTo(-hw * 0.56, -hh * 0.30)
    ..quadraticBezierTo(0, -hh * 0.33, hw * 0.56, -hh * 0.30)
    ..quadraticBezierTo(hw * 0.60, -hh * 0.02, hw * 0.54, hh * 0.22)
    ..quadraticBezierTo(0, hh * 0.25, -hw * 0.54, hh * 0.22)
    ..quadraticBezierTo(-hw * 0.60, -hh * 0.02, -hw * 0.56, -hh * 0.30);
  canvas.drawPath(beltP, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.004
    ..color = const Color(0x30FFFFFF));

  // ── 17. Body character lines (side creases) ──
  for (final side in [-1.0, 1.0]) {
    canvas.drawLine(
      Offset(hw * 0.80 * side, -hh * 0.42),
      Offset(hw * 0.78 * side, hh * 0.38),
      Paint()..color = const Color(0x18000020)..strokeWidth = s * 0.003..strokeCap = StrokeCap.round,
    );
  }

  // ── 18. B-pillar (door divider) ──
  for (final side in [-1.0, 1.0]) {
    canvas.drawLine(
      Offset(hw * 0.52 * side, -hh * 0.02),
      Offset(hw * 0.50 * side, hh * 0.06),
      Paint()..color = const Color(0x14000000)..strokeWidth = s * 0.003..strokeCap = StrokeCap.round,
    );
  }

  // ── 19. Body edge highlight (chrome outline) ──
  canvas.drawPath(body, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.005
    ..shader = ui.Gradient.linear(
      Offset(-hw, -hh * 0.3), Offset(hw, hh * 0.3),
      [const Color(0x00FFFFFF), const Color(0x28FFFFFF), const Color(0x00FFFFFF)],
      [0.0, 0.45, 1.0],
    ),
  );

  // ── 20. Direction indicator (driver self only) ──
  if (isDriverSelf) {
    final ay = -hh * 0.78;
    canvas.drawPath(
      Path()
        ..moveTo(0, ay - s * 0.04)
        ..lineTo(-s * 0.024, ay + s * 0.01)
        ..lineTo(0, ay - s * 0.005)
        ..lineTo(s * 0.024, ay + s * 0.01)
        ..close(),
      Paint()..color = acc.primary.withOpacity(0.85),
    );
  }

  canvas.restore();

  // Rasterise
  final pic = rec.endRecording();
  try {
    final img = await pic.toImage(s.toInt(), s.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (data != null) {
      return BitmapDescriptor.bytes(data.buffer.asUint8List(), imagePixelRatio: 2.0);
    }
  } catch (_) {
    // toImage can fail on very low zoom / tiny canvas – fall back gracefully
  }
  return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
}

// ═══════════════════════════════════════════════════════════════════════════
//  GEOMETRY  –  Sedan body outline (smooth, 3/4 perspective feel)
// ═══════════════════════════════════════════════════════════════════════════

/// Sedan body path.  Origin at (0,0) = centre.  Front = negative Y.
Path _bodyPath(double hw, double hh) {
  return Path()
    // Front nose (narrow, aero-rounded)
    ..moveTo(-hw * 0.38, -hh * 0.72)
    ..cubicTo(-hw * 0.42, -hh * 0.82, -hw * 0.14, -hh * 0.92, 0, -hh * 0.92)
    ..cubicTo( hw * 0.14, -hh * 0.92,  hw * 0.42, -hh * 0.82, hw * 0.38, -hh * 0.72)
    // Right front fender (widens)
    ..cubicTo(hw * 0.72, -hh * 0.62, hw * 0.88, -hh * 0.44, hw * 0.90, -hh * 0.20)
    // Right side (slight belly curve)
    ..cubicTo(hw * 0.92, hh * 0.05, hw * 0.92, hh * 0.25, hw * 0.88, hh * 0.42)
    // Right rear fender
    ..cubicTo(hw * 0.84, hh * 0.56, hw * 0.68, hh * 0.68, hw * 0.38, hh * 0.74)
    // Rear (slightly squared)
    ..cubicTo(hw * 0.16, hh * 0.80, hw * 0.06, hh * 0.82, 0, hh * 0.82)
    ..cubicTo(-hw * 0.06, hh * 0.82, -hw * 0.16, hh * 0.80, -hw * 0.38, hh * 0.74)
    // Left rear fender
    ..cubicTo(-hw * 0.68, hh * 0.68, -hw * 0.84, hh * 0.56, -hw * 0.88, hh * 0.42)
    // Left side
    ..cubicTo(-hw * 0.92, hh * 0.25, -hw * 0.92, hh * 0.05, -hw * 0.90, -hh * 0.20)
    // Left front fender
    ..cubicTo(-hw * 0.88, -hh * 0.44, -hw * 0.72, -hh * 0.62, -hw * 0.38, -hh * 0.72)
    ..close();
}

/// Realistic wheel: dark rubber tyre, metallic alloy rim, chrome hub-cap.
void _drawWheel(Canvas c, double cx, double cy, double rw, double rh, double s) {
  // Rubber tyre
  c.drawOval(
    Rect.fromCenter(center: Offset(cx, cy), width: rw * 2, height: rh * 2),
    Paint()..color = const Color(0xFF1A1A22),
  );
  // Alloy rim (metallic gradient)
  c.drawOval(
    Rect.fromCenter(center: Offset(cx, cy), width: rw * 1.30, height: rh * 1.30),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx - rw * 0.35, cy), Offset(cx + rw * 0.35, cy),
        [const Color(0xFF505060), const Color(0xFFBBBBCC), const Color(0xFF505060)],
        [0.0, 0.5, 1.0],
      ),
  );
  // Chrome centre cap
  c.drawCircle(Offset(cx, cy), rw * 0.25, Paint()..color = const Color(0xFF888899));
}
