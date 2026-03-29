import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  MWAMBA PREMIUM VEHICLE MARKER SYSTEM
//  Isometric 3/4-view car with multi-angle pre-rendering, state colouring,
//  and zoom-adaptive sizing.  Comparable to Uber / Yango quality.
// ═════════════════════════════════════════════════════════════════════════════

/// Ride-state driven colour scheme.
enum VehicleState { available, enRoute, arrived, inProgress }

/// Returns the appropriate car icon pixel size for a given map [zoom] level.
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

// ── Colour palettes per state ─────────────────────────────────────────────
class _Palette {
  final Color bodyLight;
  final Color bodyMid;
  final Color bodyDark;
  final Color accent;      // headlights / halo tint
  final Color roofLight;
  final Color roofDark;

  const _Palette({
    required this.bodyLight,
    required this.bodyMid,
    required this.bodyDark,
    required this.accent,
    required this.roofLight,
    required this.roofDark,
  });
}

const _palettes = <VehicleState, _Palette>{
  VehicleState.available: _Palette(
    bodyLight:  Color(0xFF2D2D42),
    bodyMid:    Color(0xFF1E1E32),
    bodyDark:   Color(0xFF0F0F1A),
    accent:     Color(0xFF4285F4),
    roofLight:  Color(0xFF3A3A56),
    roofDark:   Color(0xFF22223A),
  ),
  VehicleState.enRoute: _Palette(
    bodyLight:  Color(0xFF1B5E20),
    bodyMid:    Color(0xFF2E7D32),
    bodyDark:   Color(0xFF1B5E20),
    accent:     Color(0xFF66BB6A),
    roofLight:  Color(0xFF43A047),
    roofDark:   Color(0xFF2E7D32),
  ),
  VehicleState.arrived: _Palette(
    bodyLight:  Color(0xFFF57F17),
    bodyMid:    Color(0xFFF9A825),
    bodyDark:   Color(0xFFF57F17),
    accent:     Color(0xFFFDD835),
    roofLight:  Color(0xFFFBC02D),
    roofDark:   Color(0xFFF9A825),
  ),
  VehicleState.inProgress: _Palette(
    bodyLight:  Color(0xFF2D2D42),
    bodyMid:    Color(0xFF1E1E32),
    bodyDark:   Color(0xFF0F0F1A),
    accent:     Color(0xFF4285F4),
    roofLight:  Color(0xFF3A3A56),
    roofDark:   Color(0xFF22223A),
  ),
};

// ══════════════════════════════════════════════════════════════════════════
//  SPRITE CACHE  –  Pre-renders 16 angles per (zoom-bucket, state) combo
// ══════════════════════════════════════════════════════════════════════════

/// Global cache:  key = "$bucket-$stateIndex-$angleSlot"
final Map<String, BitmapDescriptor> _spriteCache = {};

/// Number of discrete angles pre-rendered.  16 → every 22.5°.
const int _angleSlots = 16;

/// Returns the [BitmapDescriptor] for a vehicle at the given [heading]°,
/// [zoom] level and visual [state].  Uses a 16-angle sprite cache.
Future<BitmapDescriptor> getVehicleMarker({
  required double heading,
  double zoom = 14,
  VehicleState state = VehicleState.available,
  bool isDriverSelf = false,
}) async {
  final size  = carSizeForZoom(zoom);
  final bucket = zoom.round();
  // Snap heading to nearest 22.5° slot
  final slot  = ((heading % 360) / (360 / _angleSlots)).round() % _angleSlots;
  final key   = '$bucket-${state.index}-$slot${isDriverSelf ? "-d" : ""}';

  if (_spriteCache.containsKey(key)) return _spriteCache[key]!;

  final angle = slot * (360.0 / _angleSlots);
  final bmp   = await _renderVehicle(
    size: size,
    heading: angle,
    state: state,
    isDriverSelf: isDriverSelf,
  );
  _spriteCache[key] = bmp;
  return bmp;
}

/// Clears the sprite cache (call on memory pressure or when not needed).
void clearVehicleCache() => _spriteCache.clear();

// ══════════════════════════════════════════════════════════════════════════
//  RENDERING ENGINE  –  Isometric 3/4-view premium sedan
// ══════════════════════════════════════════════════════════════════════════

Future<BitmapDescriptor> _renderVehicle({
  required double size,
  required double heading,
  required VehicleState state,
  required bool isDriverSelf,
}) async {
  final s = size * 2;  // 2× for Retina
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, s, s));
  final c = s / 2;
  final pal = _palettes[state]!;

  canvas.save();
  canvas.translate(c, c);
  canvas.rotate(heading * math.pi / 180);
  canvas.translate(-c, -c);

  final bw = s * 0.30;   // body half-width
  final bh = s * 0.42;   // body half-height (3/4 view = shorter ratio)
  final isoSkew = s * 0.04; // slight isometric offset

  // ── Ambient shadow (soft, no hard edge) ──
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(c + isoSkew * 0.5, c + s * 0.03),
      width: bw * 2.2,
      height: bh * 1.6,
    ),
    Paint()
      ..color = const Color(0x38000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.045),
  );

  // ── Driver-self halo ring ──
  if (isDriverSelf) {
    canvas.drawCircle(
      Offset(c, c),
      s * 0.46,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(c, c),
          s * 0.46,
          [
            pal.accent.withOpacity(0.0),
            pal.accent.withOpacity(0.08),
            pal.accent.withOpacity(0.18),
            pal.accent.withOpacity(0.0),
          ],
          [0.0, 0.55, 0.78, 1.0],
        ),
    );
  }

  // ── Main body ──
  final body = _isometricBody(c, c, bw, bh, isoSkew);
  canvas.drawPath(
    body,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(c - bw, c),
        Offset(c + bw, c),
        [pal.bodyDark, pal.bodyMid, pal.bodyLight, pal.bodyMid, pal.bodyDark],
        [0.0, 0.2, 0.5, 0.8, 1.0],
      ),
  );

  // Longitudinal reflection
  canvas.drawPath(
    body,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(c, c - bh),
        Offset(c, c + bh),
        [
          const Color(0x22FFFFFF),
          const Color(0x08FFFFFF),
          const Color(0x00000000),
          const Color(0x06FFFFFF),
        ],
        [0.0, 0.25, 0.60, 1.0],
      ),
  );

  // ── Hood panel (darker) ──
  final hood = Path()
    ..moveTo(c - bw * 0.68, c - bh * 0.52)
    ..quadraticBezierTo(c, c - bh * 0.60, c + bw * 0.68, c - bh * 0.52)
    ..lineTo(c + bw * 0.62, c - bh * 0.30)
    ..quadraticBezierTo(c, c - bh * 0.35, c - bw * 0.62, c - bh * 0.30)
    ..close();
  canvas.drawPath(hood, Paint()..color = const Color(0x28000000));

  // Hood chrome accent line
  canvas.drawLine(
    Offset(c - bw * 0.50, c - bh * 0.52),
    Offset(c + bw * 0.50, c - bh * 0.52),
    Paint()
      ..color = const Color(0x25FFFFFF)
      ..strokeWidth = s * 0.004
      ..strokeCap = StrokeCap.round,
  );

  // ── Front windshield (tinted, with reflection) ──
  _drawWindshield(
    canvas, c, c - bh * 0.28,
    bw * 0.56, bh * 0.13,
    bw * 0.08,
    isRear: false,
  );

  // ── Rear windshield ──
  _drawWindshield(
    canvas, c, c + bh * 0.22,
    bw * 0.48, bh * 0.10,
    bw * 0.06,
    isRear: true,
  );

  // ── Roof ──
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(c, c - bh * 0.04),
        width: bw * 1.02,
        height: bh * 0.30,
      ),
      Radius.circular(bw * 0.14),
    ),
    Paint()
      ..shader = ui.Gradient.radial(
        Offset(c - bw * 0.12, c - bh * 0.09),
        bw * 0.65,
        [pal.roofLight, pal.roofDark],
      ),
  );

  // Roof specular highlight
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(c - bw * 0.10, c - bh * 0.08),
        width: bw * 0.42,
        height: bh * 0.08,
      ),
      Radius.circular(bw * 0.21),
    ),
    Paint()..color = const Color(0x1AFFFFFF),
  );

  // ── Headlights (LED strip) ──
  for (final dx in [-1.0, 1.0]) {
    final hx = c + bw * 0.48 * dx;
    final hy = c - bh * 0.55;
    // Glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(hx, hy), width: bw * 0.34, height: bh * 0.05),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(hx, hy), bw * 0.18,
          [const Color(0xBBFFFFFF), const Color(0x00FFFFFF)],
        ),
    );
    // LED bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(hx, hy), width: bw * 0.22, height: bh * 0.025),
        Radius.circular(bh * 0.013),
      ),
      Paint()..color = const Color(0xFFF0F4FF),
    );
  }

  // ── Taillights (LED red) ──
  for (final dx in [-1.0, 1.0]) {
    final tx = c + bw * 0.46 * dx;
    final ty = c + bh * 0.55;
    // Glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(tx, ty), width: bw * 0.30, height: bh * 0.04),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(tx, ty), bw * 0.16,
          [const Color(0xBBFF2222), const Color(0x00FF2222)],
        ),
    );
    // LED bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(tx, ty), width: bw * 0.20, height: bh * 0.022),
        Radius.circular(bh * 0.011),
      ),
      Paint()..color = const Color(0xFFEE2020),
    );
  }

  // ── Wheels (rubber + alloy + spokes) ──
  for (final fy in [-0.32, 0.30]) {
    for (final fx in [-1.0, 1.0]) {
      _drawWheel(canvas, c + bw * 0.88 * fx, c + bh * fy, bw * 0.16, bh * 0.10, s);
    }
  }

  // ── Side mirrors ──
  for (final dx in [-1.0, 1.0]) {
    final mx = c + bw * 0.92 * dx;
    final my = c - bh * 0.22;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(mx, my), width: bw * 0.14, height: bh * 0.045),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(mx - bw * 0.05, my),
          Offset(mx + bw * 0.05, my),
          [const Color(0xFF555566), const Color(0xFFBBBBCC), const Color(0xFF555566)],
          [0.0, 0.5, 1.0],
        ),
    );
  }

  // ── Door seams ──
  final seam = Paint()
    ..color = const Color(0x14000000)
    ..strokeWidth = s * 0.003
    ..style = PaintingStyle.stroke;
  for (final dx in [-1.0, 1.0]) {
    canvas.drawLine(
      Offset(c + bw * 0.78 * dx, c - bh * 0.14),
      Offset(c + bw * 0.78 * dx, c + bh * 0.18),
      seam,
    );
  }

  // ── Centre ridge (subtle) ──
  canvas.drawLine(
    Offset(c, c - bh * 0.50),
    Offset(c, c + bh * 0.50),
    Paint()
      ..color = const Color(0x0AFFFFFF)
      ..strokeWidth = s * 0.004,
  );

  // ── Direction indicator (small chevron at front) ──
  if (isDriverSelf) {
    final ay = c - bh * 0.62;
    final chevron = Path()
      ..moveTo(c, ay - s * 0.035)
      ..lineTo(c - s * 0.028, ay + s * 0.012)
      ..lineTo(c, ay)
      ..lineTo(c + s * 0.028, ay + s * 0.012)
      ..close();
    canvas.drawPath(
      chevron,
      Paint()..color = pal.accent.withOpacity(0.75),
    );
  }

  canvas.restore();

  // Rasterise
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
  return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
}

// ══════════════════════════════════════════════════════════════════════════
//  GEOMETRY  –  Isometric sedan body
// ══════════════════════════════════════════════════════════════════════════

Path _isometricBody(double cx, double cy, double hw, double hh, double iso) {
  return Path()
    // Front nose (tapered)
    ..moveTo(cx - hw * 0.54, cy - hh * 0.46)
    ..cubicTo(
      cx - hw * 0.58, cy - hh * 0.56,
      cx - hw * 0.26, cy - hh * 0.62,
      cx, cy - hh * 0.64,
    )
    ..cubicTo(
      cx + hw * 0.26, cy - hh * 0.62,
      cx + hw * 0.58, cy - hh * 0.56,
      cx + hw * 0.54, cy - hh * 0.46,
    )
    // Right flank (fender bulge)
    ..cubicTo(
      cx + hw * 0.84, cy - hh * 0.36,
      cx + hw * 0.88, cy - hh * 0.08,
      cx + hw * 0.86, cy + hh * 0.12,
    )
    ..cubicTo(
      cx + hw * 0.88, cy + hh * 0.32,
      cx + hw * 0.84, cy + hh * 0.42,
      cx + hw * 0.54, cy + hh * 0.48,
    )
    // Rear (rounded)
    ..cubicTo(
      cx + hw * 0.26, cy + hh * 0.58,
      cx + hw * 0.12, cy + hh * 0.60,
      cx, cy + hh * 0.60,
    )
    ..cubicTo(
      cx - hw * 0.12, cy + hh * 0.60,
      cx - hw * 0.26, cy + hh * 0.58,
      cx - hw * 0.54, cy + hh * 0.48,
    )
    // Left flank
    ..cubicTo(
      cx - hw * 0.84, cy + hh * 0.42,
      cx - hw * 0.88, cy + hh * 0.32,
      cx - hw * 0.86, cy + hh * 0.12,
    )
    ..cubicTo(
      cx - hw * 0.88, cy - hh * 0.08,
      cx - hw * 0.84, cy - hh * 0.36,
      cx - hw * 0.54, cy - hh * 0.46,
    )
    ..close();
}

void _drawWindshield(
  Canvas canvas, double cx, double cy, double hw, double hh, double r,
  {required bool isRear}
) {
  final rrect = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset(cx, cy), width: hw * 2, height: hh * 2),
    Radius.circular(r),
  );
  // Tinted glass
  canvas.drawRRect(
    rrect,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx, cy - hh),
        Offset(cx, cy + hh),
        isRear
            ? [const Color(0xFF1A2636), const Color(0xFF2A3A50)]
            : [const Color(0xFF2A3A50), const Color(0xFF1A2636)],
      ),
  );
  // Sky reflection band
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx - hw * 0.22, cy - hh * 0.30),
        width: hw * 0.55,
        height: hh * 0.35,
      ),
      Radius.circular(r * 0.5),
    ),
    Paint()..color = const Color(0x1CFFFFFF),
  );
}

void _drawWheel(Canvas canvas, double cx, double cy, double hw, double hh, double s) {
  // Tire (dark rubber)
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: hw * 2, height: hh * 2),
      Radius.circular(hw * 0.42),
    ),
    Paint()..color = const Color(0xFF111118),
  );
  // Alloy rim
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: hw * 1.25, height: hh * 1.25),
      Radius.circular(hw * 0.38),
    ),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx - hw * 0.3, cy),
        Offset(cx + hw * 0.3, cy),
        [const Color(0xFF444455), const Color(0xFFAAAABB), const Color(0xFF444455)],
        [0.0, 0.5, 1.0],
      ),
  );
  // Centre hub
  canvas.drawCircle(
    Offset(cx, cy),
    hw * 0.22,
    Paint()..color = const Color(0xFF666677),
  );
}
