import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/presence/widgets/staff_marker_icon.dart';

void main() {
  const ring = Color(0xFFFFFFFF);
  const staleRing = Color(0xFF9E9E9E);
  const halo = Color(0xFF2196F3);
  const color = Color(0xFFEF5350);

  test('renderBytes returns non-empty PNG bytes', () async {
    final bytes = await StaffMarkerIconRenderer.renderBytes(
      name: 'Alice Tremblay',
      color: color,
      stale: false,
      selected: false,
      ringColor: ring,
      staleRingColor: staleRing,
      haloColor: halo,
      devicePixelRatio: 2,
    );

    expect(bytes, isNotEmpty);
    // PNG magic bytes.
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('resolve caches the identical object for the same key', () {
    final renderer = StaffMarkerIconRenderer();
    Future<Object?> pin({bool selected = false, bool stale = false}) =>
        renderer.resolve(
          name: 'Alice Tremblay',
          color: color,
          stale: stale,
          selected: selected,
          ringColor: ring,
          staleRingColor: staleRing,
          haloColor: halo,
          devicePixelRatio: 2,
        );

    final a = pin();
    final b = pin();
    expect(identical(a, b), isTrue);
  });

  test('resolve returns distinct objects across stale/selected variants', () {
    final renderer = StaffMarkerIconRenderer();
    Future<Object?> pin({required bool selected, required bool stale}) =>
        renderer.resolve(
          name: 'Alice Tremblay',
          color: color,
          stale: stale,
          selected: selected,
          ringColor: ring,
          staleRingColor: staleRing,
          haloColor: halo,
          devicePixelRatio: 2,
        );

    final normal = pin(selected: false, stale: false);
    final stale = pin(selected: false, stale: true);
    final selected = pin(selected: true, stale: false);

    expect(identical(normal, stale), isFalse);
    expect(identical(normal, selected), isFalse);
    expect(identical(stale, selected), isFalse);
  });
}
