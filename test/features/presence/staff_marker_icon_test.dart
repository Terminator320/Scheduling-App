import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/presence/widgets/staff_marker_icon.dart';

void main() {
  const ring = Color(0xFFFFFFFF);
  const halo = Color(0xFF2196F3);
  const color = Color(0xFFEF5350);

  test('renderBytes returns non-empty PNG bytes', () async {
    final bytes = await StaffMarkerIconRenderer.renderBytes(
      name: 'Alice Tremblay',
      color: color,
      selected: false,
      ringColor: ring,
      haloColor: halo,
      devicePixelRatio: 2,
    );

    expect(bytes, isNotEmpty);
    // PNG magic bytes.
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('resolve caches the identical object for the same key', () {
    final renderer = StaffMarkerIconRenderer();
    Future<Object?> pin({bool selected = false}) => renderer.resolve(
      name: 'Alice Tremblay',
      color: color,
      selected: selected,
      ringColor: ring,
      haloColor: halo,
      devicePixelRatio: 2,
    );

    final a = pin();
    final b = pin();
    expect(identical(a, b), isTrue);
  });

  test('resolve returns distinct objects across selected variants', () {
    final renderer = StaffMarkerIconRenderer();
    Future<Object?> pin({required bool selected}) => renderer.resolve(
      name: 'Alice Tremblay',
      color: color,
      selected: selected,
      ringColor: ring,
      haloColor: halo,
      devicePixelRatio: 2,
    );

    final normal = pin(selected: false);
    final selected = pin(selected: true);

    expect(identical(normal, selected), isFalse);
  });
}
