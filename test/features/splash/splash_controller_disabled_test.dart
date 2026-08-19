import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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
      FlutterSecureStorage.setMockInitialValues({});
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
          (_) async => const UserUidMatch(
            id: 'doc1',
            data: {
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
        (_) async => const UserUidMatch(
          id: 'doc1',
          data: {
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

    test('routes an invited user to setup and KEEPS the session', () async {
      // Deliberate change from the code-flow era, which signed invited users
      // out here. An admin-created account is mid-setup, not unauthorized:
      // the credential they just signed in with is exactly the one the setup
      // screen needs, so signing them out makes setup unreachable. The
      // account stays `invited`, so firestore.rules still grants it nothing.
      when(() => mockRepo.findUserByUid('uid1')).thenAnswer(
        (_) async => const UserUidMatch(
          id: 'doc1',
          data: {
            'uid': 'uid1',
            'role': 'employee',
            'status': 'invited',
            'name': 'Jane Doe',
            'firstName': 'Jane',
            'lastName': 'Doe',
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

      expect(result, isA<SplashGoToAccountSetup>());
      expect((result as SplashGoToAccountSetup).firstName, 'Jane');
      verifyNever(() => mockAuth.signOut());
    });

    test('returns SplashGoToLogin for a doc with empty status', () async {
      // C1 edge case: empty status must also fail the gate, not just
      // exact-match 'disabled'. This is why the setup branch above tests
      // `isInvited` (an exact match) rather than `!isActive` — widening it
      // would route an empty or unknown status into setup instead of out.
      when(() => mockRepo.findUserByUid('uid1')).thenAnswer(
        (_) async => const UserUidMatch(
          id: 'doc1',
          data: {
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

    test(
      'returns SplashGoToLogin for a missing doc even if sign-out throws',
      () async {
        when(() => mockRepo.findUserByUid('uid1')).thenAnswer((_) async => null);
        when(() => mockAuth.signOut()).thenThrow(Exception('ios signOut failed'));

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

    test(
      'returns SplashGoToLogin for a disabled employee even if sign-out throws',
      () async {
        when(() => mockRepo.findUserByUid('uid1')).thenAnswer(
          (_) async => const UserUidMatch(
            id: 'doc1',
            data: {
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
        when(() => mockAuth.signOut()).thenThrow(Exception('ios signOut failed'));

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

    test('rethrows when findUserByUid throws (transient errors)', () async {
      // M8: transient Firestore failures must rethrow, not sign out, so the splash UI can surface an error and retry.
      when(
        () => mockRepo.findUserByUid('uid1'),
      ).thenThrow(Exception('network down'));

      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
          employeesRepositoryProvider.overrideWithValue(mockRepo),
        ],
        // Match the app's ProviderScope: retry disabled so the transient
        // error propagates instead of being retried in the background.
        retry: (retryCount, error) => null,
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
