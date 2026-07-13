import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/maps/domain/route_url_builder.dart';

void main() {
  test('single stop becomes destination only', () {
    final uri = buildGoogleMapsRouteUrl(['12 Main St, Gatineau']);
    expect(uri, isNotNull);
    expect(uri!.queryParameters['destination'], '12 Main St, Gatineau');
    expect(uri.queryParameters.containsKey('waypoints'), isFalse);
  });

  test('multiple stops: last is destination, rest are ordered waypoints', () {
    final uri = buildGoogleMapsRouteUrl(['A St', 'B St', 'C St'])!;
    expect(uri.queryParameters['destination'], 'C St');
    expect(uri.queryParameters['waypoints'], 'A St|B St');
    expect(uri.queryParameters['travelmode'], 'driving');
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/dir/');
  });

  test('blank stops are skipped; all blank returns null', () {
    final uri = buildGoogleMapsRouteUrl(['  ', 'B St', ''])!;
    expect(uri.queryParameters['destination'], 'B St');
    expect(buildGoogleMapsRouteUrl(['', '  ']), isNull);
    expect(buildGoogleMapsRouteUrl(const []), isNull);
  });

  test('apartment suffix is stripped like AddressMapLauncher', () {
    final uri = buildGoogleMapsRouteUrl(['12 Main St apt 4, Gatineau'])!;
    expect(uri.queryParameters['destination'], isNot(contains('apt')));
    expect(uri.queryParameters['destination'], '12 Main St, Gatineau');
  });

  test('caps at 10 stops', () {
    final stops = List.generate(14, (i) => 'Stop $i');
    final uri = buildGoogleMapsRouteUrl(stops)!;
    expect(uri.queryParameters['destination'], 'Stop 9');
    expect(uri.queryParameters['waypoints']!.split('|'), hasLength(9));
  });
}
