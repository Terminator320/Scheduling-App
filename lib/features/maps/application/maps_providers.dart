import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/maps/data/google_places_repository.dart';
import 'package:scheduling/features/maps/domain/places_repository.dart';

final placesRepositoryProvider = Provider<PlacesRepository>(
  (ref) => GooglePlacesRepository(),
);

/// Family key for [reverseGeocodeProvider]. Rounds coordinates to a ~110m
/// cell so nearby GPS fixes share one billable lookup, and carries [locale]
/// so a language switch doesn't serve back a cached address in the wrong language.
@immutable
class ReverseGeocodeQuery {
  ReverseGeocodeQuery({
    required double lat,
    required double lng,
    required this.locale,
  }) : lat = double.parse(lat.toStringAsFixed(3)),
       lng = double.parse(lng.toStringAsFixed(3));

  final double lat;
  final double lng;
  final String locale;

  @override
  bool operator ==(Object other) =>
      other is ReverseGeocodeQuery &&
      other.lat == lat &&
      other.lng == lng &&
      other.locale == locale;

  @override
  int get hashCode => Object.hash(lat, lng, locale);
}

/// Resolves the display address for a rounded lat/lng cell (see
/// [ReverseGeocodeQuery]). A successful lookup is kept alive for the session,
/// while a failure stays autoDispose so it retries later. The widget should
/// treat an [AsyncError] here as "no address available" rather than a notice.
final reverseGeocodeProvider = FutureProvider.autoDispose
    .family<String?, ReverseGeocodeQuery>((ref, key) async {
      final repo = ref.watch(placesRepositoryProvider);
      final address = await repo.reverseGeocode(
        lat: key.lat,
        lng: key.lng,
        locale: key.locale,
      );
      ref.keepAlive();
      return address;
    });
