import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:scheduling/core/permissions/media_permission_service.dart' show MediaPermissionService;

/// Outcome of a location-permission request.
enum LocationPermissionResult {
  granted,
  denied,
  permanentlyDenied,
  servicesDisabled,
}

/// Wraps the runtime location permission for presence tracking. With both
/// usage-description keys in Info.plist, iOS runs the provisional-Always flow
/// (the user sees the while-in-use prompt; iOS confirms Always later), so
/// `whileInUse` and `always` both map to [LocationPermissionResult.granted] —
/// while-in-use is a working degraded mode (no background delivery, the
/// server's address fallback covers it), never an error.
///
/// **Always escalation:** background presence (and the "time to leave" pushes)
/// only keep updating while the app is closed under an *Always* grant. So on
/// the first-grant path — right after the initial while-in-use prompt is
/// answered — we request once more to surface iOS's "Change to Always Allow?"
/// upgrade. iOS shows that prompt at most once, and we deliberately do NOT
/// re-request when a returning user is *already* while-in-use, so a user who
/// chose to keep while-in-use is never nagged on subsequent launches.
///
/// Injectable function fields for tests; mirrors [MediaPermissionService].
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
      // Fresh while-in-use grant: ask again to escalate to Always so the
      // background stream survives the app being closed. Only on this
      // first-grant path — never for an already-while-in-use returning user.
      if (permission == LocationPermission.whileInUse) {
        permission = await _requestPermission();
      }
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
