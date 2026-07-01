import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/adaptive/app_scroll_behavior.dart';

Widget _host(TargetPlatform platform) => MaterialApp(
  theme: ThemeData(platform: platform),
  scrollBehavior: const AppScrollBehavior(),
  home: Scaffold(
    body: ListView.builder(
      itemCount: 100,
      itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
    ),
  ),
);

void main() {
  testWidgets('wraps scrollables in CupertinoScrollbar on iOS', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.iOS));
    expect(find.byType(CupertinoScrollbar), findsOneWidget);
  });

  testWidgets('no CupertinoScrollbar on Android', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.android));
    expect(find.byType(CupertinoScrollbar), findsNothing);
  });
}
