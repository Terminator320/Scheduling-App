import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Outcome of a location-permission request.
enum LocationPermissionResult {
  granted,
  denied,
  permanentlyDenied,
  servicesDisabled,
}

/// Wraps runtime location permission for presence tracking. Both whileInUse
/// and always count as granted access.
///
/// **Never request an Always upgrade.** The app ships without the `location`
/// UIBackgroundModes entry (App Store guideline 2.5.4 — see the presence
/// invariant in CLAUDE.md), so an Always grant would buy nothing while making
/// the app look like it tracks staff off-shift. A pre-existing Always grant
/// from an older build still maps to `granted`; we simply never ask for one.
class LocationPermissionService {
  LocationPermissionService({
    Future<bool> Function()? isServiceEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
  }) : _isServiceEnabled =
           isServiceEnabled ?? Geolocator.isLocationServiceEnabled,
       _checkPermission = checkPermission ?? Geolocator.checkPermission,
       _requestPermission = requestPermission ?? Geolocator.requestPermission;

  final Future<bool> Function() _isServiceEnabled;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;

  Future<LocationPermissionResult> ensureLocation() async {
    if (!await _isServiceEnabled()) {
      return LocationPermissionResult.servicesDisabled;
    }
    var permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _requestPermission();
    }
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionResult.granted;
      case LocationPermission.deniedForever:
        return LocationPermissionResult.permanentlyDenied;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationPermissionResult.denied;
    }
  }
}

final locationPermissionServiceProvider = Provider<LocationPermissionService>(
  (ref) => LocationPermissionService(),
);
