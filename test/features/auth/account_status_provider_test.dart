import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}
class _MockUser extends Mock implements User {}
class _MockRepo extends Mock implements EmployeesRepository {}

void main() {
  group('accountDisabledProvider', () {
    late _MockFirebaseAuth mockAuth;
    late _MockUser mockUser;
    late _MockRepo mockRepo;

    setUp(() {
      mockAuth = _MockFirebaseAuth();
      mockUser = _MockUser();
      mockRepo = _MockRepo();
    });

    ProviderContainer _container() => ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        employeesRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );

    test('emits false when no user is logged in', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      final container = _container();
      addTearDown(container.dispose);

      final result = await container.read(accountDisabledProvider.future);
      expect(result, isFalse);
    });

    test('emits true when watchUserStatus returns disabled', () async {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.uid).thenReturn('uid1');
      when(() => mockRepo.watchUserStatus('uid1'))
          .thenAnswer((_) => Stream.value('disabled'));

      final container = _container();
      addTearDown(container.dispose);

      final result = await container.read(accountDisabledProvider.future);
      expect(result, isTrue);
    });

    test('emits false when watchUserStatus returns active', () async {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.uid).thenReturn('uid1');
      when(() => mockRepo.watchUserStatus('uid1'))
          .thenAnswer((_) => Stream.value('active'));

      final container = _container();
      addTearDown(container.dispose);

      final result = await container.read(accountDisabledProvider.future);
      expect(result, isFalse);
    });
  });
}
