// The signature decides whether the live map redraws at all, so a field it
// forgets means staff pins silently stop following that field with no error
// anywhere. Every contributing field gets its own case below.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/presence/domain/live_map_aggregator.dart';
import 'package:scheduling/features/presence/domain/staff_marker_assembly.dart';
import 'package:scheduling/features/presence/widgets/staff_marker_icon.dart';

class _MockRenderer extends Mock implements StaffMarkerIconRenderer {}

StaffMapPoint point({
  String id = 'u1',
  String name = 'Ana Blake',
  Color color = const Color(0xFF112233),
  double lat = 45.5,
  double lng = -73.6,
}) => StaffMapPoint(
  userDocId: id,
  name: name,
  color: color,
  lat: lat,
  lng: lng,
  updatedAt: DateTime(2026, 8, 19, 9),
);

StaffMarkerParams params({
  List<StaffMapPoint>? points,
  String? selectedDocId,
  double devicePixelRatio = 2,
  Color ringColor = const Color(0xFFFFFFFF),
  Color haloColor = const Color(0xFF0000FF),
}) => (
  points: points ?? [point()],
  selectedDocId: selectedDocId,
  devicePixelRatio: devicePixelRatio,
  ringColor: ringColor,
  haloColor: haloColor,
);

void main() {
  group('staffMarkerSignature', () {
    test('is stable for the same inputs', () {
      expect(staffMarkerSignature(params()), staffMarkerSignature(params()));
    });

    test('changes when the device pixel ratio changes', () {
      expect(
        staffMarkerSignature(params(devicePixelRatio: 3)),
        isNot(staffMarkerSignature(params())),
      );
    });

    test('changes when the selection changes', () {
      expect(
        staffMarkerSignature(params(selectedDocId: 'u1')),
        isNot(staffMarkerSignature(params())),
      );
    });

    test('changes when the ring colour changes', () {
      expect(
        staffMarkerSignature(params(ringColor: const Color(0xFF000000))),
        isNot(staffMarkerSignature(params())),
      );
    });

    test('changes when the halo colour changes', () {
      expect(
        staffMarkerSignature(params(haloColor: const Color(0xFF00FF00))),
        isNot(staffMarkerSignature(params())),
      );
    });

    test('changes when a person moves', () {
      expect(
        staffMarkerSignature(
          params(points: [point(lat: 45.6)]),
        ),
        isNot(staffMarkerSignature(params())),
      );
      expect(
        staffMarkerSignature(
          params(points: [point(lng: -73.7)]),
        ),
        isNot(staffMarkerSignature(params())),
      );
    });

    test('changes when a person is renamed', () {
      expect(
        staffMarkerSignature(
          params(points: [point(name: 'Ana Cole')]),
        ),
        isNot(staffMarkerSignature(params())),
      );
    });

    test('changes when a crew colour changes', () {
      expect(
        staffMarkerSignature(
          params(points: [point(color: const Color(0xFF445566))]),
        ),
        isNot(staffMarkerSignature(params())),
      );
    });

    test('changes when someone joins or leaves the roster', () {
      expect(
        staffMarkerSignature(
          params(
            points: [
              point(),
              point(id: 'u2', name: 'Bo Diaz'),
            ],
          ),
        ),
        isNot(staffMarkerSignature(params())),
      );
      expect(
        staffMarkerSignature(params(points: const [])),
        isNot(staffMarkerSignature(params())),
      );
    });

    test('separates fields so a shift between them still changes it', () {
      // Without the delimiters, ('ab', 'c') and ('a', 'bc') would collide.
      expect(
        staffMarkerSignature(
          params(
            points: [point(id: 'ab', name: 'c')],
          ),
        ),
        isNot(
          staffMarkerSignature(
            params(
              points: [point(id: 'a', name: 'bc')],
            ),
          ),
        ),
      );
    });
  });

  group('assembleStaffMarkers', () {
    late _MockRenderer renderer;

    setUpAll(() {
      registerFallbackValue(const Color(0xFF000000));
    });

    setUp(() {
      renderer = _MockRenderer();
      when(
        () => renderer.resolve(
          name: any(named: 'name'),
          color: any(named: 'color'),
          selected: any(named: 'selected'),
          ringColor: any(named: 'ringColor'),
          haloColor: any(named: 'haloColor'),
          devicePixelRatio: any(named: 'devicePixelRatio'),
        ),
      ).thenAnswer((_) async => BitmapDescriptor.defaultMarker);
    });

    test('emits one marker per point, positioned at its fix', () async {
      final markers = await assembleStaffMarkers(
        params: params(
          points: [
            point(),
            point(id: 'u2', name: 'Bo Diaz', lat: 46, lng: -71),
          ],
        ),
        renderer: renderer,
        onMarkerTap: (_) {},
      );

      expect(markers.map((m) => m.markerId.value).toSet(), {'u1', 'u2'});
      final second = markers.firstWhere((m) => m.markerId.value == 'u2');
      expect(second.position, const LatLng(46, -71));
    });

    test('renders only the selected person as selected', () async {
      await assembleStaffMarkers(
        params: params(
          points: [
            point(),
            point(id: 'u2', name: 'Bo Diaz'),
          ],
          selectedDocId: 'u2',
        ),
        renderer: renderer,
        onMarkerTap: (_) {},
      );

      verify(
        () => renderer.resolve(
          name: 'Ana Blake',
          color: any(named: 'color'),
          selected: false,
          ringColor: any(named: 'ringColor'),
          haloColor: any(named: 'haloColor'),
          devicePixelRatio: any(named: 'devicePixelRatio'),
        ),
      ).called(1);
      verify(
        () => renderer.resolve(
          name: 'Bo Diaz',
          color: any(named: 'color'),
          selected: true,
          ringColor: any(named: 'ringColor'),
          haloColor: any(named: 'haloColor'),
          devicePixelRatio: any(named: 'devicePixelRatio'),
        ),
      ).called(1);
    });

    test('a tap reports the doc id of the marker tapped', () async {
      final tapped = <String>[];
      final markers = await assembleStaffMarkers(
        params: params(
          points: [
            point(),
            point(id: 'u2', name: 'Bo Diaz'),
          ],
        ),
        renderer: renderer,
        onMarkerTap: tapped.add,
      );

      for (final marker in markers) {
        marker.onTap!();
      }

      expect(tapped.toSet(), {'u1', 'u2'});
    });

    test('one failed icon aborts the whole batch', () async {
      // The caller relies on this: it keeps the previous markers and
      // signature so the next data or theme change retries.
      when(
        () => renderer.resolve(
          name: 'Bo Diaz',
          color: any(named: 'color'),
          selected: any(named: 'selected'),
          ringColor: any(named: 'ringColor'),
          haloColor: any(named: 'haloColor'),
          devicePixelRatio: any(named: 'devicePixelRatio'),
        ),
      ).thenAnswer((_) async => throw StateError('boom'));

      await expectLater(
        assembleStaffMarkers(
          params: params(
            points: [
              point(),
              point(id: 'u2', name: 'Bo Diaz'),
            ],
          ),
          renderer: renderer,
          onMarkerTap: (_) {},
        ),
        throwsStateError,
      );
    });

    test('an empty roster produces no markers', () async {
      final markers = await assembleStaffMarkers(
        params: params(points: const []),
        renderer: renderer,
        onMarkerTap: (_) {},
      );

      expect(markers, isEmpty);
    });
  });
}
