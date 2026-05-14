import 'dart:async';

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

    /// Collects the first emitted value from [accountDisabledProvider].
    Future<bool> firstValue(ProviderContainer container) {
      final completer = Completer<bool>();
      final sub = container.listen<AsyncValue<bool>>(
        accountDisabledProvider,
        (_, next) {
          if (next.hasValue && !completer.isCompleted) {
            completer.complete(next.value!);
          }
        },
        fireImmediately: true,
      );
      return completer.future.whenComplete(sub.close);
    }

    test('emits false when no user is logged in', () async {
      when(() => mockAuth.authStateChanges())
          .thenAnswer((_) => Stream.value(null));

      final container = _container();
      addTearDown(container.dispose);

      final result = await firstValue(container);
      expect(result, isFalse);
    });

    test('emits true when watchUserStatus returns disabled', () async {
      when(() => mockUser.uid).thenReturn('uid1');
      when(() => mockRepo.watchUserStatus('uid1'))
          .thenAnswer((_) => Stream.value('disabled'));
      when(() => mockAuth.authStateChanges())
          .thenAnswer((_) => Stream.value(mockUser));

      final container = _container();
      addTearDown(container.dispose);

      final result = await firstValue(container);
      expect(result, isTrue);
    });

    test('emits false when watchUserStatus returns active', () async {
      when(() => mockUser.uid).thenReturn('uid1');
      when(() => mockRepo.watchUserStatus('uid1'))
          .thenAnswer((_) => Stream.value('active'));
      when(() => mockAuth.authStateChanges())
          .thenAnswer((_) => Stream.value(mockUser));

      final container = _container();
      addTearDown(container.dispose);

      final result = await firstValue(container);
      expect(result, isFalse);
    });

    test('emits false then true when status changes from active to disabled', () async {
      when(() => mockUser.uid).thenReturn('uid1');

      // Use a StreamController to push multiple values
      final statusController = StreamController<String>();
      when(() => mockRepo.watchUserStatus('uid1'))
          .thenAnswer((_) => statusController.stream);

      // Also stub authStateChanges to emit the user
      when(() => mockAuth.authStateChanges())
          .thenAnswer((_) => Stream.value(mockUser));

      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
          employeesRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(statusController.close);

      // Attach a listener so the provider stays alive
      final emissions = <bool>[];
      final sub = container.listen(accountDisabledProvider, (_, next) {
        if (next.hasValue) emissions.add(next.value!);
      });
      addTearDown(sub.close);

      statusController.add('active');
      await Future<void>.delayed(Duration.zero);
      statusController.add('disabled');
      await Future<void>.delayed(Duration.zero);

      expect(emissions, contains(false));
      expect(emissions, contains(true));
    });
  });
}
