import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockRepo extends Mock implements EmployeesRepository {}

void main() {
  group('currentUserDocProvider', () {
    late _MockFirebaseAuth mockAuth;
    late _MockUser mockUser;
    late _MockRepo mockRepo;

    setUp(() {
      mockAuth = _MockFirebaseAuth();
      mockUser = _MockUser();
      mockRepo = _MockRepo();
    });

    test('waits for auth uid to settle before opening watchUserDoc', () async {
      final authStates = StreamController<User?>();
      when(
        () => mockAuth.authStateChanges(),
      ).thenAnswer((_) => authStates.stream);
      when(() => mockUser.uid).thenReturn('uid1');
      when(
        () => mockRepo.watchUserDoc('uid1'),
      ).thenAnswer((_) => Stream.value({'status': 'active'}));

      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
          employeesRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(authStates.close);
      addTearDown(container.dispose);

      container.listen(currentUserDocProvider, (_, _) {});
      await pumpEventQueue();
      verifyNever(() => mockRepo.watchUserDoc(any()));

      authStates.add(mockUser);
      await pumpEventQueue();

      verify(() => mockRepo.watchUserDoc('uid1')).called(1);
    });
  });

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
        // Dispose the container before closing the stream. Riverpod 3 pauses unlistened
        // providers, so closing first would hang waiting for a done event that never comes.
        addTearDown(statusController.close);
        addTearDown(container.dispose);

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
    const populated = AsyncData<Map<String, dynamic>>({'status': 'active'});

    test('false when not signed in', () {
      expect(
        isAccountDeletionSignal(
          isSignedIn: false,
          resolvedUid: 'uid1',
          previous: populated,
          docState: emptyData,
        ),
        isFalse,
      );
    });

    test('false when the auth uid has not resolved yet', () {
      // On a fresh sign-in, FirebaseAuth.currentUser is already set, but
      // authStateChanges() lags behind, so the provider still serves the
      // uid==null placeholder doc.
      expect(
        isAccountDeletionSignal(
          isSignedIn: true,
          resolvedUid: null,
          previous: populated,
          docState: emptyData,
        ),
        isFalse,
      );
    });

    test('false while the doc is reloading (isLoading)', () {
      final reloading = const AsyncLoading<Map<String, dynamic>>()
          // copyWithPrevious is @internal in Riverpod 3, but this test must
          // reproduce the exact reload transition the framework emits.
          // ignore: invalid_use_of_internal_member
          .copyWithPrevious(populated);
      expect(
        isAccountDeletionSignal(
          isSignedIn: true,
          resolvedUid: 'uid1',
          previous: populated,
          docState: reloading,
        ),
        isFalse,
      );
    });

    test('false when the settled doc is non-empty', () {
      expect(
        isAccountDeletionSignal(
          isSignedIn: true,
          resolvedUid: 'uid1',
          previous: emptyData,
          docState: populated,
        ),
        isFalse,
      );
    });

    test('true for a populated -> empty transition (real deletion)', () {
      expect(
        isAccountDeletionSignal(
          isSignedIn: true,
          resolvedUid: 'uid1',
          previous: populated,
          docState: emptyData,
        ),
        isTrue,
      );
    });

    test('true across a loading blip: retained-populated -> empty', () {
      final reloadingPopulated = const AsyncLoading<Map<String, dynamic>>()
          // No public API builds a loading state that retains prior data, so
          // copyWithPrevious is used here to mirror a live reload blip over a populated doc.
          // ignore: invalid_use_of_internal_member
          .copyWithPrevious(populated);
      expect(
        isAccountDeletionSignal(
          isSignedIn: true,
          resolvedUid: 'uid1',
          previous: reloadingPopulated,
          docState: emptyData,
        ),
        isTrue,
      );
    });

    test(
      'false for a settled empty doc that was never populated (fresh sign-in '
      'lag / invited-signup bootstrap window)',
      () {
        // There's no prior data (first emission), or just a prior empty placeholder,
        // so the empty doc reads as a bootstrap window, not a populated->empty deletion.
        expect(
          isAccountDeletionSignal(
            isSignedIn: true,
            resolvedUid: 'uid1',
            previous: null,
            docState: emptyData,
          ),
          isFalse,
        );
        expect(
          isAccountDeletionSignal(
            isSignedIn: true,
            resolvedUid: 'uid1',
            previous: emptyData,
            docState: emptyData,
          ),
          isFalse,
        );
      },
    );
  });

  group('confirmColdStartDeletion (C3: deleted while the app was closed)', () {
    const emptyData = AsyncData<Map<String, dynamic>>({});
    const populated = AsyncData<Map<String, dynamic>>({'status': 'active'});
    const cachedIdentity = EmployeeRecord(
      id: 'doc1',
      uid: 'uid1',
      name: 'George',
      status: 'active',
    );

    test(
      'flags a warm-cache cold start whose users doc is confirmed absent',
      () async {
        // This simulates a cold start after a server-side deletion — splash's cache-hit
        // path routed straight to the calendar, so the doc's first settled emission
        // is a clean empty with no populated previous.
        expect(
          await confirmColdStartDeletion(
            isSignedIn: true,
            resolvedUid: 'uid1',
            previous: null,
            docState: emptyData,
            loadWarmCache: (uid) async => uid == 'uid1' ? cachedIdentity : null,
          ),
          isTrue,
        );
      },
    );

    test(
      'does not flag the fresh-signup window (signed in, no doc yet, '
      'cold cache)',
      () async {
        var cacheReads = 0;
        expect(
          await confirmColdStartDeletion(
            isSignedIn: true,
            resolvedUid: 'uid1',
            previous: null,
            docState: emptyData,
            loadWarmCache: (uid) async {
              cacheReads++;
              return null; // The cache only exists after a completed sign-in.
            },
          ),
          isFalse,
        );
        expect(cacheReads, 1);
      },
    );

    test('does not flag a transient permission-denied (stream error)', () async {
      var cacheReads = 0;
      final denied = AsyncError<Map<String, dynamic>>(
        Exception('permission-denied'),
        StackTrace.current,
      );
      expect(
        await confirmColdStartDeletion(
          isSignedIn: true,
          resolvedUid: 'uid1',
          previous: null,
          docState: denied,
          loadWarmCache: (uid) async {
            cacheReads++;
            return cachedIdentity;
          },
        ),
        isFalse,
      );
      // An error emission must never even consult the cache.
      expect(cacheReads, 0);
    });

    test('does not flag while the doc is still loading or populated', () async {
      expect(
        await confirmColdStartDeletion(
          isSignedIn: true,
          resolvedUid: 'uid1',
          previous: null,
          docState: const AsyncLoading(),
          loadWarmCache: (uid) async => cachedIdentity,
        ),
        isFalse,
      );
      expect(
        await confirmColdStartDeletion(
          isSignedIn: true,
          resolvedUid: 'uid1',
          previous: null,
          docState: populated,
          loadWarmCache: (uid) async => cachedIdentity,
        ),
        isFalse,
      );
    });

    test(
      'leaves the populated→empty transition to isAccountDeletionSignal',
      () async {
        // The live-deletion listener already handles this shape. Cold-start
        // confirmation only owns the never-populated case.
        expect(
          isColdStartDeletionCandidate(
            isSignedIn: true,
            resolvedUid: 'uid1',
            previous: populated,
            docState: emptyData,
          ),
          isFalse,
        );
      },
    );

    test('does not flag when signed out or the uid is unresolved', () async {
      expect(
        await confirmColdStartDeletion(
          isSignedIn: false,
          resolvedUid: 'uid1',
          previous: null,
          docState: emptyData,
          loadWarmCache: (uid) async => cachedIdentity,
        ),
        isFalse,
      );
      expect(
        await confirmColdStartDeletion(
          isSignedIn: true,
          resolvedUid: null,
          previous: null,
          docState: emptyData,
          loadWarmCache: (uid) async => cachedIdentity,
        ),
        isFalse,
      );
    });

    test('fails safe when the cache read itself throws', () async {
      expect(
        await confirmColdStartDeletion(
          isSignedIn: true,
          resolvedUid: 'uid1',
          previous: null,
          docState: emptyData,
          loadWarmCache: (uid) async => throw Exception('keystore'),
        ),
        isFalse,
      );
    });
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
      // Same teardown ordering as the status test above: dispose before close.
      addTearDown(roleController.close);
      addTearDown(container.dispose);

      final emissions = <String>[];
      final sub = container.listen(userRoleProvider, (_, next) {
        if (next.hasValue) emissions.add(next.value!);
      });
      addTearDown(sub.close);

      roleController.add({'role': 'admin'});
      await pumpEventQueue();
      roleController.add({'role': 'employee'});
      await pumpEventQueue();

      // Sequencing matters here — admin has to appear before employee, or the
      // main.dart listener can't detect the admin → employee demotion.
      expect(emissions, containsAllInOrder(['admin', 'employee']));
    });
  });

  group('currentUserNameProvider', () {
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

    Future<String> firstNameValue(ProviderContainer container) async {
      final sub = container.listen<String>(currentUserNameProvider, (_, _) {});
      addTearDown(sub.close);
      // The doc listener opens behind an async auth-uid gate, so the name is
      // empty by definition until the doc lands - settle it before reading.
      await container.read(currentUserDocProvider.future);
      return container.read(currentUserNameProvider);
    }

    test('falls back to first and last name when name is blank', () async {
      when(() => mockUser.uid).thenReturn('uid1');
      when(
        () => mockRepo.watchUserDoc('uid1'),
      ).thenAnswer((_) => Stream.value({
        'firstName': 'Theo',
        'lastName': 'Roy',
        'status': 'active',
      }));
      when(
        () => mockAuth.authStateChanges(),
      ).thenAnswer((_) => Stream.value(mockUser));

      final container = container0();
      addTearDown(container.dispose);

      expect(await firstNameValue(container), 'Theo Roy');
    });

    test('falls back to email when the doc has no name fields', () async {
      when(() => mockUser.uid).thenReturn('uid1');
      when(
        () => mockRepo.watchUserDoc('uid1'),
      ).thenAnswer((_) => Stream.value({
        'email': 'theo@example.com',
        'status': 'active',
      }));
      when(
        () => mockAuth.authStateChanges(),
      ).thenAnswer((_) => Stream.value(mockUser));

      final container = container0();
      addTearDown(container.dispose);

      expect(await firstNameValue(container), 'theo@example.com');
    });
  });
}
