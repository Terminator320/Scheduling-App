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

  /// Fake whose successive request() calls return [answers] in order (the last
  /// value repeats once exhausted), so escalation — a second request — can be
  /// distinguished from the first.
  LocationPermissionService escalatingService(
    List<LocationPermission> answers, {
    LocationPermission current = LocationPermission.denied,
  }) {
    var i = 0;
    return LocationPermissionService(
      isServiceEnabled: () async => true,
      checkPermission: () async => current,
      requestPermission: () async {
        final answer = answers[i < answers.length ? i : answers.length - 1];
        i++;
        return answer;
      },
    );
  }

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
        
      ).ensureLocation(),
      LocationPermissionResult.denied,
    );
  });

  test('fresh while-in-use grant escalates to Always', () async {
    // First request → whileInUse, second (escalation) → always.
    final svc = escalatingService([
      LocationPermission.whileInUse,
      LocationPermission.always,
    ]);
    expect(await svc.ensureLocation(), LocationPermissionResult.granted);
  });

  test('escalation that stays while-in-use is still granted', () async {
    // User keeps while-in-use on the upgrade prompt — a working degraded mode.
    final svc = escalatingService([
      LocationPermission.whileInUse,
      LocationPermission.whileInUse,
    ]);
    expect(await svc.ensureLocation(), LocationPermissionResult.granted);
  });

  test('already while-in-use is NOT re-requested (no nagging)', () async {
    var requests = 0;
    final svc = LocationPermissionService(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      requestPermission: () async {
        requests++;
        return LocationPermission.always;
      },
    );
    expect(await svc.ensureLocation(), LocationPermissionResult.granted);
    expect(requests, isZero);
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
