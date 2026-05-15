import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/splash/application/splash_controller.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockRepo extends Mock implements EmployeesRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('splashDestinationProvider — disabled account', () {
    late _MockFirebaseAuth mockAuth;
    late _MockUser mockUser;
    late _MockRepo mockRepo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockAuth = _MockFirebaseAuth();
      mockUser = _MockUser();
      mockRepo = _MockRepo();
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.uid).thenReturn('uid1');
      when(() => mockAuth.signOut()).thenAnswer((_) async {});
    });

    test(
      'returns SplashGoToLogin and signs out for a disabled employee',
      () async {
        when(() => mockRepo.findUserByUid('uid1')).thenAnswer(
          (_) async => UserUidMatch(
            id: 'doc1',
            data: const {
              'uid': 'uid1',
              'role': 'employee',
              'status': 'disabled',
              'name': 'Jane',
              'email': 'jane@example.com',
              'phone': '',
              'colorValue': '4280391411',
            },
          ),
        );

        final container = ProviderContainer(
          overrides: [
            firebaseAuthProvider.overrideWithValue(mockAuth),
            employeesRepositoryProvider.overrideWithValue(mockRepo),
          ],
        );
        addTearDown(container.dispose);

        final result = await container.read(splashDestinationProvider.future);

        expect(result, isA<SplashGoToLogin>());
        verify(() => mockAuth.signOut()).called(1);
      },
    );

    test('returns SplashGoToCalendar for an active employee', () async {
      when(() => mockRepo.findUserByUid('uid1')).thenAnswer(
        (_) async => UserUidMatch(
          id: 'doc1',
          data: const {
            'uid': 'uid1',
            'role': 'employee',
            'status': 'active',
            'name': 'Jane',
            'email': 'jane@example.com',
            'phone': '',
            'colorValue': '4280391411',
          },
        ),
      );

      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
          employeesRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(splashDestinationProvider.future);

      expect(result, isA<SplashGoToCalendar>());
      verifyNever(() => mockAuth.signOut());
    });

    test('returns SplashGoToLogin and signs out for an invited user', () async {
      // C1: the gate must require status == 'active', not just block
      // 'disabled'. Invited users have a Firestore doc but no completed
      // sign-up flow — they must not enter the app.
      when(() => mockRepo.findUserByUid('uid1')).thenAnswer(
        (_) async => UserUidMatch(
          id: 'doc1',
          data: const {
            'uid': 'uid1',
            'role': 'employee',
            'status': 'invited',
            'name': 'Jane',
            'email': 'jane@example.com',
            'phone': '',
            'colorValue': '4280391411',
          },
        ),
      );

      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
          employeesRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(splashDestinationProvider.future);

      expect(result, isA<SplashGoToLogin>());
      verify(() => mockAuth.signOut()).called(1);
    });

    test('returns SplashGoToLogin for a doc with empty status', () async {
      // C1 edge case: malformed user doc (status defaulted to '') must also
      // fail the gate. Without this, any future status value would slip
      // through if it didn't exactly equal 'disabled'.
      when(() => mockRepo.findUserByUid('uid1')).thenAnswer(
        (_) async => UserUidMatch(
          id: 'doc1',
          data: const {
            'uid': 'uid1',
            'role': 'employee',
            'status': '',
            'name': 'Jane',
            'email': 'jane@example.com',
            'phone': '',
            'colorValue': '4280391411',
          },
        ),
      );

      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
          employeesRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(splashDestinationProvider.future);

      expect(result, isA<SplashGoToLogin>());
      verify(() => mockAuth.signOut()).called(1);
    });

    test('rethrows when findUserByUid throws (transient errors)', () async {
      // M8: transient Firestore failures (network, unavailable) must not
      // silently sign the user out. The provider rethrows so the splash UI
      // can surface an error and the user can retry.
      when(
        () => mockRepo.findUserByUid('uid1'),
      ).thenThrow(Exception('network down'));

      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
          employeesRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(splashDestinationProvider.future),
        throwsA(isA<Exception>()),
      );
      verifyNever(() => mockAuth.signOut());
    });
  });
}
