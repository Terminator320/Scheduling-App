import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/adaptive/app_scroll_behavior.dart';
import 'package:scheduling/core/layout/master_detail_scaffold.dart';
import 'package:scheduling/core/layout/primary_scroll_scope.dart';

Widget _list(String keyPrefix) => ListView.builder(
  primary: true,
  itemCount: 50,
  itemBuilder: (_, i) => SizedBox(
    height: 48,
    child: Text('$keyPrefix-$i'),
  ),
);

Widget _harness({required Widget child}) => MaterialApp(
  scrollBehavior: const AppScrollBehavior(),
  // Forces the CupertinoScrollbar path, which requires its controller to
  // hold exactly ONE ScrollPosition — the regression this pins.
  theme: ThemeData(platform: TargetPlatform.iOS),
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'two primary lists side by side each get their own scroll scope and '
    'scrolling never throws "attached to more than one ScrollPosition"',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _harness(
          child: MasterDetailScaffold(
            master: _list('master'),
            detail: _list('detail'),
            placeholder: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PrimaryScrollScope), findsNWidgets(2));
      expect(find.text('master-0'), findsOneWidget);
      expect(find.text('detail-0'), findsOneWidget);

      await tester.drag(find.text('master-0'), const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.drag(find.text('detail-0'), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('below the tablet breakpoint only the master renders', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        child: MasterDetailScaffold(
          master: _list('master'),
          detail: _list('detail'),
          placeholder: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('master-0'), findsOneWidget);
    expect(find.text('detail-0'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
