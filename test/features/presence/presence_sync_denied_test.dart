import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/permissions/location_permission_service.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';
import 'package:scheduling/features/presence/data/presence_repository.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockEmployeesRepo extends Mock implements EmployeesRepository {}

class _MockPresenceRepo extends Mock implements PresenceRepository {}

class _MockPermissions extends Mock implements LocationPermissionService {}

/// Feeds positions on demand and reports whether the app cancelled its
/// subscription — which is the observable half of `_stop()`.
class _FakeGeolocator extends GeolocatorPlatform {
  late final StreamController<Position> _controller =
      StreamController<Position>(onCancel: () => cancelled = true);

  bool cancelled = false;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      _controller.stream;

  void emit(Position position) => _controller.add(position);
}

Position _position() => Position(
  latitude: 45.5,
  longitude: -73.6,
  timestamp: DateTime(2026, 7, 8, 12),
  accuracy: 10,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockAuth auth;
  late _MockUser user;
  late _MockEmployeesRepo employees;
  late _MockPresenceRepo presence;
  late _MockPermissions permissions;
  late _FakeGeolocator geolocator;

  setUp(() {
    auth = _MockAuth();
    user = _MockUser();
    employees = _MockEmployeesRepo();
    presence = _MockPresenceRepo();
    permissions = _MockPermissions();
    geolocator = _FakeGeolocator();
    GeolocatorPlatform.instance = geolocator;

    when(() => user.uid).thenReturn('uid-1');
    when(() => auth.currentUser).thenReturn(user);
    when(
      () => permissions.ensureLocation(),
    ).thenAnswer((_) async => LocationPermissionResult.granted);
    when(
      () => employees.findUserByUid(any()),
    ).thenAnswer((_) async => const UserUidMatch(id: 'doc-1', data: {}));
    when(
      () => presence.deleteLocation(userDocId: any(named: 'userDocId')),
    ).thenAnswer((_) async {});
  });

  ProviderContainer makeContainer() => ProviderContainer(
    overrides: [
      currentUserDocProvider.overrideWith(
        (ref) => Stream.value(const {'role': 'employee', 'status': 'active'}),
      ),
      employeesRepositoryProvider.overrideWithValue(employees),
      presenceRepositoryProvider.overrideWithValue(presence),
      locationPermissionServiceProvider.overrideWithValue(permissions),
      presenceSyncControllerProvider.overrideWith(
        (ref) => PresenceSyncController(ref, auth: auth),
      ),
    ],
  );

  /// Starts the position stream and pushes one fix through it.
  Future<PresenceSyncController> trackOneFix(
    ProviderContainer container,
  ) async {
    final sub = container.listen(currentUserDocProvider, (_, _) {});
    addTearDown(sub.close);
    await pumpEventQueue();

    final controller = container.read(presenceSyncControllerProvider);
    await controller.sync();
    geolocator.emit(_position());
    await pumpEventQueue();
    return controller;
  }

  test('a denied write cancels the position stream', () async {
    // Without this, a disabled employee's phone keeps streaming location and
    // hammering Firestore with rejected writes indefinitely.
    when(
      () => presence.upsertLocation(
        userDocId: any(named: 'userDocId'),
        uid: any(named: 'uid'),
        lat: any(named: 'lat'),
        lng: any(named: 'lng'),
      ),
    ).thenAnswer((_) async => PresenceWriteResult.denied);

    final container = makeContainer();
    addTearDown(container.dispose);
    await trackOneFix(container);

    expect(geolocator.cancelled, isTrue);
  });

  test('a transient failure keeps the position stream running', () async {
    when(
      () => presence.upsertLocation(
        userDocId: any(named: 'userDocId'),
        uid: any(named: 'uid'),
        lat: any(named: 'lat'),
        lng: any(named: 'lng'),
      ),
    ).thenAnswer((_) async => PresenceWriteResult.failed);

    final container = makeContainer();
    addTearDown(container.dispose);
    await trackOneFix(container);

    expect(geolocator.cancelled, isFalse);
  });

  test('a denied write drops the tracked doc, so unregister has nothing to '
      'delete', () async {
    when(
      () => presence.upsertLocation(
        userDocId: any(named: 'userDocId'),
        uid: any(named: 'uid'),
        lat: any(named: 'lat'),
        lng: any(named: 'lng'),
      ),
    ).thenAnswer((_) async => PresenceWriteResult.denied);

    final container = makeContainer();
    addTearDown(container.dispose);
    final controller = await trackOneFix(container);
    await controller.unregister();

    verifyNever(
      () => presence.deleteLocation(userDocId: any(named: 'userDocId')),
    );
  });
}
