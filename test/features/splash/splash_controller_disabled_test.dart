import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      mockAuth = _MockFirebaseAuth();
      mockUser = _MockUser();
      mockRepo = _MockRepo();
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.uid).thenReturn('uid1');
      when(() => mockAuth.signOut()).thenAnswer((_) async {});
    });

    test('returns SplashGoToLogin and signs out for a disabled employee', () async {
      when(() => mockRepo.findUserByUid('uid1')).thenAnswer(
        (_) async => UserUidMatch(id: 'doc1', data: const {
          'uid': 'uid1',
          'role': 'employee',
          'status': 'disabled',
          'name': 'Jane',
          'email': 'jane@example.com',
          'phone': '',
          'colorValue': '4280391411',
        }),
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

    test('returns SplashGoToCalendar for an active employee', () async {
      when(() => mockRepo.findUserByUid('uid1')).thenAnswer(
        (_) async => UserUidMatch(id: 'doc1', data: const {
          'uid': 'uid1',
          'role': 'employee',
          'status': 'active',
          'name': 'Jane',
          'email': 'jane@example.com',
          'phone': '',
          'colorValue': '4280391411',
        }),
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
    });
  });
}
