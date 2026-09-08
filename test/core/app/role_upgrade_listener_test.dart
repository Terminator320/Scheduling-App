import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/app/role_upgrade_listener.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/navigation/hub_shell_scope.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';

/// Records the tab switch instead of driving a real hub, so the assertion is
/// the navigation the listener asked for rather than a rendered screen.
class _RecordingSelector implements HubTabSelector {
  final List<({HubTab tab, bool isAdmin, String employeeId})> selections = [];

  @override
  void select(
    HubTab tab, {
    required bool isAdmin,
    required String employeeId,
    String userName = '',
    String userEmail = '',
  }) => selections.add((tab: tab, isAdmin: isAdmin, employeeId: employeeId));

  @override
  void selectAndReveal(
    HubTab tab, {
    required bool isAdmin,
    required String employeeId,
    String userName = '',
    String userEmail = '',
  }) => select(
    tab,
    isAdmin: isAdmin,
    employeeId: employeeId,
    userName: userName,
    userEmail: userEmail,
  );

  @override
  void goHome() {}
}

void main() {
  late StreamController<Map<String, dynamic>> docs;
  late _RecordingSelector selector;

  setUp(() {
    docs = StreamController<Map<String, dynamic>>.broadcast();
    selector = _RecordingSelector();
  });

  tearDown(() => docs.close());

  Widget listenerIn(ProviderContainer container, {bool isAdmin = false}) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: HubShellScope(
            shell: selector,
            current: HubTab.calendar,
            child: RoleUpgradeListener(
              employeeId: 'doc-1',
              isAdmin: isAdmin,
              child: const SizedBox(),
            ),
          ),
        ),
      );

  ProviderContainer containerFor(Stream<Map<String, dynamic>> stream) {
    final container = ProviderContainer(
      overrides: [currentUserDocProvider.overrideWith((ref) => stream)],
    )..listen(currentUserDocProvider, (_, _) {});
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpListener(WidgetTester tester, {bool isAdmin = false}) =>
      tester.pumpWidget(
        listenerIn(containerFor(docs.stream), isAdmin: isAdmin),
      );

  testWidgets('a role already admin at mount still re-routes', (tester) async {
    // The eager read: `ref.listen` fires only on a CHANGE, so an admin role
    // that had already SETTLED before this mounted would otherwise never reach
    // the listener and the person would keep the employee shell all session.
    final container = containerFor(
      Stream.value(const {'role': 'admin', 'status': 'active'}),
    );
    await container.read(currentUserDocProvider.future);

    await tester.pumpWidget(listenerIn(container));
    await tester.pumpAndSettle();

    expect(selector.selections.single.tab, HubTab.calendar);
  });

  testWidgets('a mid-session promotion re-routes as admin', (tester) async {
    await pumpListener(tester);
    docs.add(const {'role': 'employee', 'status': 'active'});
    await tester.pumpAndSettle();
    docs.add(const {'role': 'admin', 'status': 'active'});
    await tester.pumpAndSettle();

    expect(selector.selections.single.isAdmin, isTrue);
  });

  testWidgets('an employee role never re-routes', (tester) async {
    await pumpListener(tester);
    docs.add(const {'role': 'employee', 'status': 'active'});
    await tester.pumpAndSettle();

    expect(selector.selections, isEmpty);
  });

  testWidgets('an existing admin is left alone', (tester) async {
    await pumpListener(tester, isAdmin: true);
    docs.add(const {'role': 'admin', 'status': 'active'});
    await tester.pumpAndSettle();

    expect(selector.selections, isEmpty);
  });

  testWidgets('a promotion re-routes once, not on every rebuild', (
    tester,
  ) async {
    await pumpListener(tester);
    docs.add(const {'role': 'admin', 'status': 'active'});
    await tester.pumpAndSettle();
    docs.add(const {'role': 'admin', 'status': 'active', 'name': 'Ada'});
    await tester.pumpAndSettle();

    expect(selector.selections, hasLength(1));
  });
}
