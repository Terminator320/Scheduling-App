import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:scheduling/core/logging/app_logger.dart';

/// Outcome of a location-permission request.
enum LocationPermissionResult {
  granted,
  denied,
  permanentlyDenied,
  servicesDisabled,
}

/// Never requests an Always upgrade. A pre-existing Always grant still counts
/// as granted.
class LocationPermissionService {
  LocationPermissionService({
    Future<bool> Function()? isServiceEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    AppLogger? logger,
  }) : _isServiceEnabled =
           isServiceEnabled ?? Geolocator.isLocationServiceEnabled,
       _checkPermission = checkPermission ?? Geolocator.checkPermission,
       _requestPermission = requestPermission ?? Geolocator.requestPermission,
       _logger = logger ?? AppLogger();

  final Future<bool> Function() _isServiceEnabled;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final AppLogger _logger;

  Future<LocationPermissionResult> ensureLocation() async {
    try {
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
    } catch (e, st) {
      _logger.warn('PERM-LOCATION ensureLocation failed', e, st);
      return LocationPermissionResult.denied;
    }
  }
}

final locationPermissionServiceProvider = Provider<LocationPermissionService>(
  (ref) => LocationPermissionService(),
);
