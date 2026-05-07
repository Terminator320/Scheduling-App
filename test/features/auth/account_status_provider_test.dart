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

    ProviderContainer container0() => ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        employeesRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );

    /// Collects the first emitted value from [accountDisabledProvider].
    Future<bool> firstValue(ProviderContainer container) {
      final completer = Completer<bool>();
      final sub = container.listen<AsyncValue<bool>>(accountDisabledProvider, (
        _,
        next,
      ) {
        if (next.hasValue && !completer.isCompleted) {
          completer.complete(next.value!);
        }
      }, fireImmediately: true);
      return completer.future.whenComplete(sub.close);
    }

    test('emits false when no user is logged in', () async {
      when(
        () => mockAuth.authStateChanges(),
      ).thenAnswer((_) => Stream.value(null));

      final container = container0();
      addTearDown(container.dispose);

      final result = await firstValue(container);
      expect(result, isFalse);
    });

    test('emits true when watchUserDoc status is disabled', () async {
      when(() => mockUser.uid).thenReturn('uid1');
      when(
        () => mockRepo.watchUserDoc('uid1'),
      ).thenAnswer((_) => Stream.value({'status': 'disabled'}));
      when(
        () => mockAuth.authStateChanges(),
      ).thenAnswer((_) => Stream.value(mockUser));

      final container = container0();
      addTearDown(container.dispose);

      final result = await firstValue(container);
      expect(result, isTrue);
    });

    test('emits false when watchUserDoc status is active', () async {
      when(() => mockUser.uid).thenReturn('uid1');
      when(
        () => mockRepo.watchUserDoc('uid1'),
      ).thenAnswer((_) => Stream.value({'status': 'active'}));
      when(
        () => mockAuth.authStateChanges(),
      ).thenAnswer((_) => Stream.value(mockUser));

      final container = container0();
      addTearDown(container.dispose);

      final result = await firstValue(container);
      expect(result, isFalse);
    });

    test(
      'emits false then true when status changes from active to disabled',
      () async {
        when(() => mockUser.uid).thenReturn('uid1');

        // Use a StreamController to push multiple values
        final statusController = StreamController<Map<String, dynamic>>();
        when(
          () => mockRepo.watchUserDoc('uid1'),
        ).thenAnswer((_) => statusController.stream);

        // Also stub authStateChanges to emit the user
        when(
          () => mockAuth.authStateChanges(),
        ).thenAnswer((_) => Stream.value(mockUser));

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

        // The doc value flows through currentUserDocProvider before
        // accountDisabledProvider derives from it, so drain the event queue
        // after each push rather than a single microtask.
        statusController.add({'status': 'active'});
        await pumpEventQueue();
        statusController.add({'status': 'disabled'});
        await pumpEventQueue();

        expect(emissions, contains(false));
        expect(emissions, contains(true));
      },
    );
  });

  group('isAccountDeletionSignal', () {
    const emptyData = AsyncData<Map<String, dynamic>>({});

    test('false when not signed in', () {
      expect(
        isAccountDeletionSignal(
          isSignedIn: false,
          resolvedUid: 'uid1',
          docState: emptyData,
        ),
        isFalse,
      );
    });

    test('false when the auth uid has not resolved yet', () {
      // Fresh sign-in: FirebaseAuth.currentUser is set but authStateChanges()
      // lags, so the provider still serves the uid==null placeholder doc.
      expect(
        isAccountDeletionSignal(
          isSignedIn: true,
          resolvedUid: null,
          docState: emptyData,
        ),
        isFalse,
      );
    });

    test(
      'false for the reload transition that retains the empty placeholder',
      () {
        // uid just resolved: provider rebuilds into AsyncLoading retaining the
        // previous empty doc via copyWithPrevious — not an authoritative delete.
        final reloading = const AsyncLoading<Map<String, dynamic>>()
            .copyWithPrevious(emptyData);
        expect(
          isAccountDeletionSignal(
            isSignedIn: true,
            resolvedUid: 'uid1',
            docState: reloading,
          ),
          isFalse,
        );
      },
    );

    test('false when the settled doc is non-empty', () {
      expect(
        isAccountDeletionSignal(
          isSignedIn: true,
          resolvedUid: 'uid1',
          docState: const AsyncData({'status': 'active'}),
        ),
        isFalse,
      );
    });

    test(
      'true for a settled empty doc with a resolved uid (real deletion)',
      () {
        expect(
          isAccountDeletionSignal(
            isSignedIn: true,
            resolvedUid: 'uid1',
            docState: emptyData,
          ),
          isTrue,
        );
      },
    );
  });

  group('userRoleProvider', () {
    late _MockFirebaseAuth mockAuth;
    late _MockUser mockUser;
    late _MockRepo mockRepo;

    setUp(() {
      mockAuth = _MockFirebaseAuth();
      mockUser = _MockUser();
      mockRepo = _MockRepo();
    });

    ProviderContainer container0() => ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        employeesRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );

    Future<String> firstRoleValue(ProviderContainer container) {
      final completer = Completer<String>();
      final sub = container.listen<AsyncValue<String>>(userRoleProvider, (
        _,
        next,
      ) {
        if (next.hasValue && !completer.isCompleted) {
          completer.complete(next.value!);
        }
      }, fireImmediately: true);
      return completer.future.whenComplete(sub.close);
    }

    test('emits empty string when no user is logged in', () async {
      when(
        () => mockAuth.authStateChanges(),
      ).thenAnswer((_) => Stream.value(null));

      final container = container0();
      addTearDown(container.dispose);

      final result = await firstRoleValue(container);
      expect(result, isEmpty);
    });

    test('emits "admin" when watchUserDoc role is admin', () async {
      when(() => mockUser.uid).thenReturn('uid1');
      when(
        () => mockRepo.watchUserDoc('uid1'),
      ).thenAnswer((_) => Stream.value({'role': 'admin'}));
      when(
        () => mockAuth.authStateChanges(),
      ).thenAnswer((_) => Stream.value(mockUser));

      final container = container0();
      addTearDown(container.dispose);

      final result = await firstRoleValue(container);
      expect(result, 'admin');
    });

    test('emits "admin" then "employee" when role is demoted', () async {
      when(() => mockUser.uid).thenReturn('uid1');

      final roleController = StreamController<Map<String, dynamic>>();
      when(
        () => mockRepo.watchUserDoc('uid1'),
      ).thenAnswer((_) => roleController.stream);
      when(
        () => mockAuth.authStateChanges(),
      ).thenAnswer((_) => Stream.value(mockUser));

      final container = container0();
      addTearDown(container.dispose);
      addTearDown(roleController.close);

      final emissions = <String>[];
      final sub = container.listen(userRoleProvider, (_, next) {
        if (next.hasValue) emissions.add(next.value!);
      });
      addTearDown(sub.close);

      roleController.add({'role': 'admin'});
      await pumpEventQueue();
      roleController.add({'role': 'employee'});
      await pumpEventQueue();

      // Sequencing matters: admin must appear before employee, otherwise the
      // main.dart listener can't detect the admin → employee demotion.
      expect(emissions, containsAllInOrder(['admin', 'employee']));
    });
  });
}
