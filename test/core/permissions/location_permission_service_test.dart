import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:scheduling/core/permissions/location_permission_service.dart';

void main() {
  LocationPermissionService service({
    bool serviceEnabled = true,
    LocationPermission current = LocationPermission.denied,
    LocationPermission afterRequest = LocationPermission.denied,
  }) => LocationPermissionService(
    isServiceEnabled: () async => serviceEnabled,
    checkPermission: () async => current,
    requestPermission: () async => afterRequest,
  );

  test('disabled location services short-circuit', () async {
    expect(
      await service(serviceEnabled: false).ensureLocation(),
      LocationPermissionResult.servicesDisabled,
    );
  });

  test('always maps to granted', () async {
    expect(
      await service(current: LocationPermission.always).ensureLocation(),
      LocationPermissionResult.granted,
    );
  });

  test('whileInUse maps to granted (working degraded mode)', () async {
    expect(
      await service(current: LocationPermission.whileInUse).ensureLocation(),
      LocationPermissionResult.granted,
    );
  });

  test('denied triggers one request and honors its answer', () async {
    expect(
      await service(
        afterRequest: LocationPermission.whileInUse,
      ).ensureLocation(),
      LocationPermissionResult.granted,
    );
    expect(
      await service(
        afterRequest: LocationPermission.denied,
      ).ensureLocation(),
      LocationPermissionResult.denied,
    );
  });

  test('deniedForever maps to permanentlyDenied without a request', () async {
    var requested = false;
    final svc = LocationPermissionService(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.deniedForever,
      requestPermission: () async {
        requested = true;
        return LocationPermission.denied;
      },
    );
    expect(
      await svc.ensureLocation(),
      LocationPermissionResult.permanentlyDenied,
    );
    expect(requested, isFalse);
  });
}
