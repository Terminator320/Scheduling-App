import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/maps/data/google_places_repository.dart';
import 'package:scheduling/features/maps/domain/places_repository.dart';

final placesRepositoryProvider = Provider<PlacesRepository>(
  (ref) => GooglePlacesRepository(),
);

/// Family key for [reverseGeocodeProvider]. The constructor rounds raw
/// coordinates to a 3-decimal-degree cell (~110m at the equator) so nearby GPS
/// fixes within the same cell share one reverse-geocode lookup instead of
/// firing a fresh billable call per fix, and carries [locale] so a language
/// switch keys a fresh lookup rather than serving the other language's cached
/// address. The cell is coarser than the presence stream's 250m fix filter so
/// a moving staff member's consecutive fixes collapse to few billable calls
/// (an ~11m cell would key a fresh lookup on almost every fix). Build it
/// directly with the raw lat/lng — it self-normalizes.
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

/// Resolves the display address for a rounded lat/lng cell (build the key with
/// [ReverseGeocodeQuery]). A successful lookup calls [Ref.keepAlive] so it
/// stays cached for the rest of the session — staff addresses don't change
/// mid-session — while a failed lookup stays autoDispose so it's retried on
/// the next watch. The widget layer should treat an [AsyncError] as "no
/// address available", not surface a notice for it.
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
