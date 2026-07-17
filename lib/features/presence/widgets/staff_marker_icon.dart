import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/shared/widgets/primitives/name_initials.dart';

/// Renders staff map-pin bitmaps for `google_maps_flutter` markers (markers are
/// bitmaps, not widgets). Draws an avatar-colored balloon with the person's
/// initials, a surface ring, and a pointer tip; dimmed with a grey ring at
/// ~50% alpha when stale, and wrapped in a primary halo when selected.
///
/// Theme colors are passed IN so the renderer stays pure and testable — it
/// never reads a `BuildContext`. Results are cached per
/// (initials, colorValue, stale, selected, ring/staleRing/halo, dpr): the same
/// key returns the identical `Future<BitmapDescriptor>`. A failed render is
/// evicted so the next resolve retries instead of caching the error.
class StaffMarkerIconRenderer {
  StaffMarkerIconRenderer();

  final Map<String, Future<BitmapDescriptor>> _cache = {};

  Future<BitmapDescriptor> resolve({
    required String name,
    required Color color,
    required bool stale,
    required bool selected,
    required Color ringColor,
    required Color staleRingColor,
    required Color haloColor,
    required double devicePixelRatio,
  }) {
    final initials = nameInitials(name);
    final key =
        '$initials|${color.toARGB32()}|$stale|$selected|'
        '${ringColor.toARGB32()}|${staleRingColor.toARGB32()}|'
        '${haloColor.toARGB32()}|${devicePixelRatio.toStringAsFixed(2)}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final future = _buildDescriptor(
      name: name,
      color: color,
      stale: stale,
      selected: selected,
      ringColor: ringColor,
      staleRingColor: staleRingColor,
      haloColor: haloColor,
      devicePixelRatio: devicePixelRatio,
    );
    _cache[key] = future;
    // Evict a failed render so the next resolve retries — but only if this
    // exact future is still cached, so a later successful render isn't dropped.
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_cache[key], future)) _cache.remove(key);
        },
      ),
    );
    return future;
  }

  Future<BitmapDescriptor> _buildDescriptor({
    required String name,
    required Color color,
    required bool stale,
    required bool selected,
    required Color ringColor,
    required Color staleRingColor,
    required Color haloColor,
    required double devicePixelRatio,
  }) async {
    final bytes = await renderBytes(
      name: name,
      color: color,
      stale: stale,
      selected: selected,
      ringColor: ringColor,
      staleRingColor: staleRingColor,
      haloColor: haloColor,
      devicePixelRatio: devicePixelRatio,
    );
    return BitmapDescriptor.bytes(bytes, imagePixelRatio: devicePixelRatio);
  }

  static const double _radius = 20;
  static const double _ringWidth = 3;
  static const double _haloWidth = 4;
  static const double _pointerHeight = 9;
  static const double _pad = 6;

  /// Draws one pin and returns its PNG bytes. Pure `dart:ui` — no plugin
  /// channels — so it runs (and is asserted on) directly in `flutter_test`.
  @visibleForTesting
  static Future<Uint8List> renderBytes({
    required String name,
    required Color color,
    required bool stale,
    required bool selected,
    required Color ringColor,
    required Color staleRingColor,
    required Color haloColor,
    required double devicePixelRatio,
  }) async {
    final initials = nameInitials(name);
    final ring = stale ? staleRingColor : ringColor;
    const width = _radius * 2 + _pad * 2;
    // Pad only on the top/sides: the canvas ends exactly at the pointer tip so
    // the marker's default (0.5, 1) anchor lands the tip on the coordinate.
    const height = _radius * 2 + _pad + _pointerHeight;
    const center = Offset(width / 2, _pad + _radius);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);

    // A single translucent layer dims the whole pin when stale.
    if (stale) {
      canvas.saveLayer(
        const Rect.fromLTWH(0, 0, width, height),
        Paint()..color = Colors.white.withValues(alpha: 0.5),
      );
    }

    if (selected) {
      canvas.drawCircle(
        center,
        _radius + _haloWidth,
        Paint()
          ..color = haloColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = _haloWidth,
      );
    }

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Pointer tip below the circle, filled to read as one balloon.
    final pointer = Path()
      ..moveTo(center.dx - 6, center.dy + _radius - 4)
      ..lineTo(center.dx + 6, center.dy + _radius - 4)
      ..lineTo(center.dx, center.dy + _radius + _pointerHeight)
      ..close();
    canvas
      ..drawPath(pointer, fillPaint)
      ..drawCircle(center, _radius, fillPaint)
      ..drawCircle(
        center,
        _radius,
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = _ringWidth,
      );

    final painter = TextPainter(
      text: TextSpan(
        text: initials,
        style: TextStyle(
          color: contrastingForegroundFor(color),
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );

    if (stale) canvas.restore();

    final image = await recorder.endRecording().toImage(
      (width * devicePixelRatio).round(),
      (height * devicePixelRatio).round(),
    );
    // Free the image even if PNG encoding throws or returns null.
    final ByteData? data;
    try {
      data = await image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      image.dispose();
    }
    if (data == null) {
      throw StateError('Failed to encode staff marker icon to PNG bytes.');
    }
    return data.buffer.asUint8List();
  }
}
