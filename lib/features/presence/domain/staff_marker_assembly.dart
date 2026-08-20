import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:scheduling/features/presence/domain/live_map_aggregator.dart';
import 'package:scheduling/features/presence/widgets/staff_marker_icon.dart';

/// Everything a batch of staff markers is derived from.
///
/// A record rather than five loose parameters because both functions below
/// take the same set, and [staffMarkerSignature] must cover every field of it
/// — the pair only stays honest if there is one place to add a field to.
typedef StaffMarkerParams = ({
  List<StaffMapPoint> points,
  String? selectedDocId,
  double devicePixelRatio,
  Color ringColor,
  Color haloColor,
});

/// A cheap identity for one marker batch, used to skip re-rendering when
/// nothing that affects a pin has changed.
///
/// This decides whether the map updates AT ALL: a field left out here means
/// staff pins silently stop following that field, with no error anywhere. It
/// must mention every member of [StaffMarkerParams] and every point field the
/// icon or the position depends on.
String staffMarkerSignature(StaffMarkerParams params) {
  final buffer = StringBuffer()
    ..write(params.devicePixelRatio)
    ..write('|')
    ..write(params.selectedDocId ?? '')
    ..write('|')
    ..write(params.ringColor.toARGB32())
    ..write(',')
    ..write(params.haloColor.toARGB32());
  for (final p in params.points) {
    buffer
      ..write(';')
      ..write(p.userDocId)
      ..write(',')
      ..write(p.lat)
      ..write(',')
      ..write(p.lng)
      ..write(',')
      ..write(p.color.toARGB32())
      ..write(',')
      ..write(p.name);
  }
  return buffer.toString();
}

/// Renders one icon per point and pairs it with its position.
///
/// Every icon renders in parallel. The renderer caches per key, so repeated or
/// superseded batches are near-free, but one failure aborts the whole batch —
/// which is deliberate: the caller keeps the previous markers and signature in
/// place so the next data or theme change retries.
Future<Set<Marker>> assembleStaffMarkers({
  required StaffMarkerParams params,
  required StaffMarkerIconRenderer renderer,
  required void Function(String userDocId) onMarkerTap,
}) async {
  final points = params.points;
  final icons = await Future.wait(
    points.map(
      (point) => renderer.resolve(
        name: point.name,
        color: point.color,
        selected: point.userDocId == params.selectedDocId,
        ringColor: params.ringColor,
        haloColor: params.haloColor,
        devicePixelRatio: params.devicePixelRatio,
      ),
    ),
  );
  final markers = <Marker>{};
  for (var i = 0; i < points.length; i++) {
    final point = points[i];
    markers.add(
      Marker(
        markerId: MarkerId(point.userDocId),
        position: LatLng(point.lat, point.lng),
        icon: icons[i],
        onTap: () => onMarkerTap(point.userDocId),
      ),
    );
  }
  return markers;
}
