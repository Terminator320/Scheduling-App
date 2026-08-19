import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/notifications/push_notification_service.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/notifications/data/fcm_token_repository.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockPushService extends Mock implements PushNotificationService {}

class _MockEmployeesRepo extends Mock implements EmployeesRepository {}

class _MockFcmRepo extends Mock implements FcmTokenRepository {}

void main() {
  late _MockAuth auth;
  late _MockUser user;
  late _MockPushService service;
  late _MockEmployeesRepo employees;
  late _MockFcmRepo fcm;

  setUp(() {
    auth = _MockAuth();
    user = _MockUser();
    service = _MockPushService();
    employees = _MockEmployeesRepo();
    fcm = _MockFcmRepo();

    when(() => user.uid).thenReturn('uid-1');
    when(() => auth.currentUser).thenReturn(user);
    when(() => service.requestPermission()).thenAnswer((_) async => true);
    when(
      () => service.configureForegroundPresentation(),
    ).thenAnswer((_) async {});
    when(() => service.currentToken()).thenAnswer((_) async => 'tok-1');
    when(() => service.onTokenRefresh).thenAnswer((_) => const Stream.empty());
    when(() => employees.findUserByUid(any())).thenAnswer(
      (_) async => const UserUidMatch(id: 'doc-1', data: {}),
    );
    when(
      () => fcm.upsertToken(
        userDocId: any(named: 'userDocId'),
        token: any(named: 'token'),
        platform: any(named: 'platform'),
        locale: any(named: 'locale'),
        uid: any(named: 'uid'),
      ),
    ).thenAnswer((_) async {});
  });

  ProviderContainer makeContainer(Map<String, dynamic> userDoc) {
    return ProviderContainer(
      overrides: [
        currentUserDocProvider.overrideWith((ref) => Stream.value(userDoc)),
        pushNotificationServiceProvider.overrideWithValue(service),
        employeesRepositoryProvider.overrideWithValue(employees),
        fcmTokenRepositoryProvider.overrideWithValue(fcm),
        pushRegistrationControllerProvider.overrideWith(
          (ref) => PushRegistrationController(ref, auth: auth),
        ),
      ],
    );
  }

  // Keeps the overridden stream provider alive and flushes its first emission
  // into `.value` (the shape `sync()` reads).
  Future<void> settleDoc(ProviderContainer container) async {
    final sub = container.listen(currentUserDocProvider, (_, _) {});
    addTearDown(sub.close);
    await pumpEventQueue();
  }

  test('signed-out user is a no-op — never touches the push service', () async {
    when(() => auth.currentUser).thenReturn(null);
    final container = makeContainer(const {});
    addTearDown(container.dispose);
    await settleDoc(container);

    await container.read(pushRegistrationControllerProvider).sync();

    verifyNever(() => service.requestPermission());
    verifyNever(() => employees.findUserByUid(any()));
  });

  test('inactive employee does not register', () async {
    final container = makeContainer(const {
      'role': 'employee',
      'status': 'invited',
    });
    addTearDown(container.dispose);
    await settleDoc(container);

    await container.read(pushRegistrationControllerProvider).sync();

    verifyNever(() => service.requestPermission());
    verifyNever(() => employees.findUserByUid(any()));
  });

  test('a loading account doc does not register yet', () async {
    final docs = StreamController<Map<String, dynamic>>();
    final container = ProviderContainer(
      overrides: [
        currentUserDocProvider.overrideWith((ref) => docs.stream),
        pushNotificationServiceProvider.overrideWithValue(service),
        employeesRepositoryProvider.overrideWithValue(employees),
        fcmTokenRepositoryProvider.overrideWithValue(fcm),
        pushRegistrationControllerProvider.overrideWith(
          (ref) => PushRegistrationController(ref, auth: auth),
        ),
      ],
    );
    addTearDown(docs.close);
    addTearDown(container.dispose);

    await container.read(pushRegistrationControllerProvider).sync();

    verifyNever(() => service.requestPermission());
    verifyNever(() => employees.findUserByUid(any()));
  });

  test('active employee registers once; second sync fast-paths', () async {
    final container = makeContainer(const {
      'role': 'employee',
      'status': 'active',
    });
    addTearDown(container.dispose);
    await settleDoc(container);

    final controller = container.read(pushRegistrationControllerProvider);
    await controller.sync();
    // Same uid + locale + live refresh subscription → the second sync must
    // skip the findUserByUid query and the token upsert entirely.
    await controller.sync();

    verify(() => employees.findUserByUid('uid-1')).called(1);
    verify(
      () => fcm.upsertToken(
        userDocId: 'doc-1',
        token: 'tok-1',
        platform: any(named: 'platform'),
        locale: 'en',
        uid: 'uid-1',
      ),
    ).called(1);
  });
}
