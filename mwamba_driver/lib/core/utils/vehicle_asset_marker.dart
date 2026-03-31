import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  VEHICLE ASSET MARKER  –  PNG-based vehicle markers
//
//  Uses assets/images/my-car.png (white sedan, transparent background,
//  facing ~315° / upper-left).  A +45° rotation offset corrects to north.
//
//  Drop-in replacement for vehicle_painter.dart — same public API:
//    getVehicleMarker(), VehicleState, carSizeForZoom(), polylineWidthForZoom()
// ═════════════════════════════════════════════════════════════════════════════

/// Ride-state enum (kept for API compatibility with call sites).
enum VehicleState { available, enRoute, arrived, inProgress }

/// Returns the car icon pixel size for a given map [zoom] level.
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

// ── Internal state ───────────────────────────────────────────────────────
ui.Image? _srcImage;
final Map<String, BitmapDescriptor> _spriteCache = {};
const int _angleSlots = 16;

/// The source PNG faces north (0° / up).  No rotation offset needed.
const double _imageRotationOffset = 0.0;

/// Load the source PNG once.
Future<void> _ensureLoaded() async {
  if (_srcImage != null) return;
  final data = await rootBundle.load('assets/images/my-car.png');
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  _srcImage = frame.image;
}

/// Drop-in replacement for the Canvas-based getVehicleMarker().
/// [state] and [isDriverSelf] are accepted for API compat but ignored
/// (the PNG already looks great without per-state halo).
Future<BitmapDescriptor> getVehicleMarker({
  required double heading,
  double zoom = 14,
  VehicleState state = VehicleState.available,
  bool isDriverSelf = false,
}) async {
  await _ensureLoaded();

  final size = carSizeForZoom(zoom);
  final bucket = size.round();
  final slot =
      ((heading % 360) / (360 / _angleSlots)).round() % _angleSlots;
  final key = '$bucket-$slot';

  if (_spriteCache.containsKey(key)) return _spriteCache[key]!;

  final angle = slot * (360.0 / _angleSlots) + _imageRotationOffset;
  final s = size * 2.0; // 2× for retina
  final canvasSize = s < 8 ? 8.0 : s;

  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, canvasSize, canvasSize));

  canvas.translate(canvasSize / 2, canvasSize / 2);
  canvas.rotate(angle * math.pi / 180);
  canvas.translate(-canvasSize / 2, -canvasSize / 2);

  final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
  canvas.drawImageRect(
    _srcImage!,
    ui.Rect.fromLTWH(
      0, 0,
      _srcImage!.width.toDouble(),
      _srcImage!.height.toDouble(),
    ),
    ui.Rect.fromLTWH(0, 0, canvasSize, canvasSize),
    paint,
  );

  final pic = rec.endRecording();
  final img = await pic.toImage(canvasSize.toInt(), canvasSize.toInt());
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();

  final bmp = byteData != null
      ? BitmapDescriptor.bytes(
          byteData.buffer.asUint8List(),
          imagePixelRatio: 2.0,
        )
      : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);

  _spriteCache[key] = bmp;
  return bmp;
}

/// Clear the sprite cache.
void clearVehicleCache() => _spriteCache.clear();
