import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/live_activity/data/live_activity_token_repository.dart';
import 'package:scheduling/features/live_activity/domain/live_activity_token.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockEmployeesRepo extends Mock implements EmployeesRepository {}

class _MockTokenRepo extends Mock implements LiveActivityTokenRepository {}

// NOTE ON COVERAGE / SKIPPED CASES
// --------------------------------
// `sync()`, `canHostCards()` and `endLocalCards()` all hard-gate on
// `dart:io Platform.isIOS` BEFORE any injectable seam. A unit-test host (this
// repo runs on Windows) reports `Platform.isIOS == false`, and `dart:io`
// exposes no way to fake it (unlike Flutter's `defaultTargetPlatform`). So the
// documented `sync()` contracts that require the body to execute —
//   (a) cold-start sync awaits the enabled-preference `ready` before acting,
//   (c) a concurrent sync coalesces into a pending resync —
// cannot run past the first line on this host, and the push-to-start / update
// token streams they drive are method-channel plugin surfaces (device-only
// verification, per CLAUDE.md). Those two cases are intentionally NOT faked.
//
// What IS tested here runs cross-platform:
//   - `unregister()` and its `_resolveUserDocId()` are NOT iOS-gated, so the
//     opt-out delete path (contract (b)) is covered in full;
//   - `sync()` / `canHostCards()` / `endLocalCards()` no-op off iOS (the slice
//     of contract (d) reachable here: this host genuinely cannot host a card).
void main() {
  late _MockAuth auth;
  late _MockUser user;
  late _MockEmployeesRepo employees;
  late _MockTokenRepo tokenRepo;

  setUpAll(() {
    registerFallbackValue(LiveActivityTokenKind.pushToStart);
    registerFallbackValue(DateTime(2026));
  });

  setUp(() {
    auth = _MockAuth();
    user = _MockUser();
    employees = _MockEmployeesRepo();
    tokenRepo = _MockTokenRepo();

    when(() => user.uid).thenReturn('uid-1');
    when(() => auth.currentUser).thenReturn(user);
    when(
      () => employees.findUserByUid(any()),
    ).thenAnswer((_) async => const UserUidMatch(id: 'doc-1', data: {}));
    when(
      () => tokenRepo.deleteTokensOfKind(
        userDocId: any(named: 'userDocId'),
        kind: LiveActivityTokenKind.pushToStart,
      ),
    ).thenAnswer((_) async {});
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        employeesRepositoryProvider.overrideWithValue(employees),
        liveActivityTokenRepositoryProvider.overrideWithValue(tokenRepo),
        liveActivityRegistrationControllerProvider.overrideWith(
          (ref) => LiveActivityRegistrationController(ref, auth: auth),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  LiveActivityRegistrationController controllerOf(ProviderContainer c) =>
      c.read(liveActivityRegistrationControllerProvider);

  group('unregister', () {
    test(
      'resolves the users-doc id itself and deletes push-to-start rows by kind '
      'even when sync() never ran',
      () async {
        final controller = controllerOf(makeContainer());

        // sync() has never run, so `_docId` is unset — unregister must resolve
        // the id from the signed-in uid on its own.
        await controller.unregister();

        verify(() => employees.findUserByUid('uid-1')).called(1);
        verify(
          () => tokenRepo.deleteTokensOfKind(
            userDocId: 'doc-1',
            kind: LiveActivityTokenKind.pushToStart,
          ),
        ).called(1);
      },
    );

    test('signed-out session deletes nothing', () async {
      when(() => auth.currentUser).thenReturn(null);
      final controller = controllerOf(makeContainer());

      await controller.unregister();

      verifyNever(() => employees.findUserByUid(any()));
      verifyNever(
        () => tokenRepo.deleteTokensOfKind(
          userDocId: any(named: 'userDocId'),
          kind: any(named: 'kind'),
        ),
      );
    });

    test('swallows a token-repo delete failure and never throws', () async {
      when(
        () => tokenRepo.deleteTokensOfKind(
          userDocId: any(named: 'userDocId'),
          kind: LiveActivityTokenKind.pushToStart,
        ),
      ).thenThrow(Exception('rules'));
      final controller = controllerOf(makeContainer());

      await expectLater(controller.unregister(), completes);
    });

    test('swallows a users-doc lookup failure and deletes nothing', () async {
      when(() => employees.findUserByUid(any())).thenThrow(Exception('denied'));
      final controller = controllerOf(makeContainer());

      await expectLater(controller.unregister(), completes);
      verifyNever(
        () => tokenRepo.deleteTokensOfKind(
          userDocId: any(named: 'userDocId'),
          kind: any(named: 'kind'),
        ),
      );
    });
  });

  group('off-iOS gates (this host cannot host a card)', () {
    test('sync() is a no-op — never resolves a doc or upserts a token',
        () async {
      final controller = controllerOf(makeContainer());

      await controller.sync();

      verifyNever(() => employees.findUserByUid(any()));
      verifyNever(
        () => tokenRepo.upsertToken(
          userDocId: any(named: 'userDocId'),
          docId: any(named: 'docId'),
          token: any(named: 'token'),
          kind: any(named: 'kind'),
          locale: any(named: 'locale'),
          uid: any(named: 'uid'),
          expiresAt: any(named: 'expiresAt'),
        ),
      );
    });

    test('canHostCards() returns false without probing the plugin', () async {
      final controller = controllerOf(makeContainer());
      expect(await controller.canHostCards(), isFalse);
    });

    test('endLocalCards() is a no-op and never throws', () async {
      final controller = controllerOf(makeContainer());
      await expectLater(controller.endLocalCards(), completes);
    });
  });
}
