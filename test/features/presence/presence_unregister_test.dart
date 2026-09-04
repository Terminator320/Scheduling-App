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

/// Counts subscriptions, which is the observable half of `_start()` — the
/// resumed body re-opening the position stream is exactly what must not happen.
class _FakeGeolocator extends GeolocatorPlatform {
  final _controller = StreamController<Position>.broadcast();
  int listens = 0;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    listens++;
    return _controller.stream;
  }
}

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
      () => employees.findUserByUid(any()),
    ).thenAnswer((_) async => const UserUidMatch(id: 'doc-1', data: {}));
    when(
      () => presence.deleteLocation(userDocId: any(named: 'userDocId')),
    ).thenAnswer((_) async {});
  });

  ProviderContainer makeContainer({
    LocationPermissionResult permission = LocationPermissionResult.granted,
  }) {
    when(
      () => permissions.ensureLocation(),
    ).thenAnswer((_) async => permission);
    final container = ProviderContainer(
      overrides: [
        currentUserDocProvider.overrideWith(
          (ref) => Stream.value(const {
            'role': 'employee',
            'status': 'active',
            'locationSharingEnabled': true,
          }),
        ),
        employeesRepositoryProvider.overrideWithValue(employees),
        presenceRepositoryProvider.overrideWithValue(presence),
        locationPermissionServiceProvider.overrideWithValue(permissions),
        presenceSyncControllerProvider.overrideWith(
          (ref) => PresenceSyncController(ref, auth: auth),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(currentUserDocProvider, (_, _) {});
    addTearDown(sub.close);
    return container;
  }

  test('a session that never started still deletes the stored fix', () async {
    // The employee revoked Location in iOS Settings, so `_start` never ran and
    // `_docId` is null - but the doc from a PREVIOUS launch is still live, and
    // a stale pin is visually identical to a fresh one on the admin map.
    final container = makeContainer(
      permission: LocationPermissionResult.denied,
    );
    await pumpEventQueue();
    final controller = container.read(presenceSyncControllerProvider);
    await controller.sync();

    await controller.unregister();

    verify(() => presence.deleteLocation(userDocId: 'doc-1')).called(1);
  });

  test('unregister deletes nothing when there is no signed-in user', () async {
    when(() => auth.currentUser).thenReturn(null);
    final container = makeContainer();
    await pumpEventQueue();

    await container.read(presenceSyncControllerProvider).unregister();

    verifyNever(
      () => presence.deleteLocation(userDocId: any(named: 'userDocId')),
    );
  });

  test(
    'a sync resuming mid-teardown does not re-create the presence doc',
    () async {
      // `deregisterThisDevice` runs BEFORE signOut(), so the resumed body still
      // holds a valid credential and its writes would SUCCEED - re-opening the
      // position stream for a user who just signed out, with nothing logging it.
      final release = Completer<UserUidMatch?>();
      final syncLookupStarted = Completer<void>();
      var call = 0;
      when(() => employees.findUserByUid(any())).thenAnswer((_) {
        call++;
        // Only the sync is held open; the teardown's own resolve must land.
        if (call == 1) {
          syncLookupStarted.complete();
          return release.future;
        }
        return Future<UserUidMatch?>.value(
          const UserUidMatch(id: 'doc-1', data: {}),
        );
      });

      final container = makeContainer();
      await pumpEventQueue();
      final controller = container.read(presenceSyncControllerProvider);

      final inFlight = controller.sync();
      await syncLookupStarted.future;
      expect(
        geolocator.listens,
        0,
        reason: 'sync is still awaiting the lookup',
      );

      await controller.unregister();
      release.complete(const UserUidMatch(id: 'doc-1', data: {}));
      await inFlight;
      await pumpEventQueue();

      verify(() => presence.deleteLocation(userDocId: 'doc-1')).called(1);
      expect(
        geolocator.listens,
        0,
        reason: 'the resumed body must not re-open the position stream',
      );
    },
  );
}
