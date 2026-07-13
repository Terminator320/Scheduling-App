import 'package:scheduling/features/maps/domain/address_parser.dart';

/// Google Maps caps directions URLs at 9 waypoints + 1 destination.
const int maxRouteStops = 10;

/// Builds a Google Maps directions URL through [addresses] in order, or null
/// when no usable stop remains. Apple Maps has no multi-stop URL scheme —
/// per-stop navigation covers those users.
Uri? buildGoogleMapsRouteUrl(List<String> addresses) {
  final stops = addresses
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty)
      .map((a) => AddressParser.splitApt(a)?.street ?? a)
      .take(maxRouteStops)
      .toList();
  if (stops.isEmpty) return null;
  final destination = stops.removeLast();
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': destination,
    if (stops.isNotEmpty) 'waypoints': stops.join('|'),
    'travelmode': 'driving',
  });
}
