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

  /// Fake whose successive request() calls step through [answers] in order,
  /// repeating the last value once exhausted. That way we can tell escalation
  /// (a second request) apart from the initial one.
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

  test('fresh while-in-use grant is NOT escalated to Always', () async {
    // The app ships without the `location` background mode (guideline 2.5.4),
    // so an Always upgrade prompt would buy nothing and would read as
    // off-shift tracking. Exactly one prompt, and whileInUse is the answer we
    // keep.
    var requests = 0;
    final svc = LocationPermissionService(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async {
        requests++;
        return LocationPermission.whileInUse;
      },
    );
    expect(await svc.ensureLocation(), LocationPermissionResult.granted);
    expect(requests, 1);
  });

  test('pre-existing Always grant is still honored', () async {
    // Users upgrading from a build that did request Always keep that grant;
    // we just never ask for it again.
    final svc = escalatingService(
      [LocationPermission.always],
      current: LocationPermission.always,
    );
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
