import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/auth/application/active_user_identity_provider.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';

class _MockEmployeesRepository extends Mock implements EmployeesRepository {}

const _uid = 'auth-uid-1';
const _docId = 'users-doc-1';

FirebaseException _permissionDenied() => FirebaseException(
  plugin: 'cloud_firestore',
  code: 'permission-denied',
);

void main() {
  late _MockEmployeesRepository repo;

  setUp(() {
    repo = _MockEmployeesRepository();
    when(() => repo.findUserByUid(any())).thenAnswer(
      (_) async => const UserUidMatch(id: _docId, data: {'role': 'employee'}),
    );
  });

  /// Container wired with an account doc + auth uid.
  ProviderContainer makeContainer({
    Map<String, dynamic> doc = const {'role': 'employee', 'status': 'active'},
    String? uid = _uid,
  }) {
    final container = ProviderContainer(
      // Mirrors main.dart's ProviderScope: Riverpod 3's default automatic
      // provider retry is off, so a failed build surfaces its error instead of
      // looping forever.
      retry: (retryCount, error) => null,
      overrides: [
        currentUserDocProvider.overrideWith((ref) => Stream.value(doc)),
        authUidProvider.overrideWith((ref) => Stream.value(uid)),
        employeesRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    // Riverpod 3 auto-disposes by default, so every provider this test reads
    // needs a live listener or its element is torn down mid-emission.
    container
      ..listen(currentUserDocProvider, (_, _) {})
      ..listen(authUidProvider, (_, _) {})
      ..listen(activeUserIdentityProvider, (_, _) {});
    return container;
  }

  /// Lets the two source streams deliver before reading the identity future —
  /// the provider rebuilds on each dependency emission and `.future` is
  /// per-build.
  Future<ActiveUserIdentity?> resolve(ProviderContainer container) async {
    await container.read(currentUserDocProvider.future);
    await container.read(authUidProvider.future);
    return container.read(activeUserIdentityProvider.future);
  }

  group('active identity', () {
    test('resolves an active employee to (employee, docId)', () async {
      final identity = await resolve(makeContainer());

      expect(identity, isNotNull);
      expect(identity!.role, 'employee');
      expect(identity.docId, _docId);
      verify(() => repo.findUserByUid(_uid)).called(1);
    });

    test('resolves an active admin to (admin, docId)', () async {
      final identity = await resolve(
        makeContainer(doc: const {'role': 'admin', 'status': 'active'}),
      );

      expect(identity?.role, 'admin');
      expect(identity?.docId, _docId);
    });

    test('the docId comes from the users doc, not the auth uid', () async {
      final identity = await resolve(makeContainer());

      expect(identity?.docId, isNot(_uid));
      expect(identity?.docId, _docId);
    });

    test('tolerates padded role/status values', () async {
      final identity = await resolve(
        makeContainer(doc: const {'role': ' admin ', 'status': ' active '}),
      );

      expect(identity?.role, 'admin');
    });
  });

  group('returns null (this is what wipes the widget + Siri mirrors)', () {
    test('when the account doc is empty (signed out)', () async {
      expect(await resolve(makeContainer(doc: const {})), isNull);
      verifyNever(() => repo.findUserByUid(any()));
    });

    test('when the account is disabled', () async {
      final identity = await resolve(
        makeContainer(doc: const {'role': 'employee', 'status': 'disabled'}),
      );

      expect(identity, isNull);
      verifyNever(() => repo.findUserByUid(any()));
    });

    test('when the account is still invited', () async {
      final identity = await resolve(
        makeContainer(doc: const {'role': 'employee', 'status': 'invited'}),
      );

      expect(identity, isNull);
    });

    test('when the status field is missing entirely', () async {
      final identity = await resolve(
        makeContainer(doc: const {'role': 'employee'}),
      );

      expect(identity, isNull);
    });

    test('when the role is neither employee nor admin', () async {
      final identity = await resolve(
        makeContainer(doc: const {'role': 'contractor', 'status': 'active'}),
      );

      expect(identity, isNull);
      verifyNever(() => repo.findUserByUid(any()));
    });

    test('when there is no auth uid', () async {
      final identity = await resolve(makeContainer(uid: null));

      expect(identity, isNull);
      verifyNever(() => repo.findUserByUid(any()));
    });

    test('when no users doc matches the uid', () async {
      when(() => repo.findUserByUid(any())).thenAnswer((_) async => null);

      expect(await resolve(makeContainer()), isNull);
    });
  });

  group('post-sign-in permission-denied retry', () {
    test('retries past a transient permission-denied and resolves', () async {
      var calls = 0;
      when(() => repo.findUserByUid(any())).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw _permissionDenied();
        return const UserUidMatch(id: _docId, data: {'role': 'employee'});
      });

      final identity = await resolve(makeContainer());

      expect(calls, 2, reason: 'the first read must be retried, not swallowed');
      expect(identity?.docId, _docId);
    });

    test('a persistent failure surfaces as an error, never a silent null', () {
      // A silent null would wipe the widget + Siri mirrors on a transient
      // failure, so exhausting the retries must propagate instead.
      when(
        () => repo.findUserByUid(any()),
      ).thenAnswer((_) async => throw _permissionDenied());

      return expectLater(
        resolve(makeContainer()),
        throwsA(isA<FirebaseException>()),
      );
    });
  });
}
