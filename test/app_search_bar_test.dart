// test/app_search_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/shared/widgets/fields/app_search_bar.dart';

void main() {
  testWidgets('AppSearchBar calls onChanged when typing', (tester) async {
    var result = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppSearchBar(
          onChanged: (v) => result = v,
          hintText: 'Search clients...',
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'Sarah');
    expect(result, 'Sarah');
  });

  testWidgets('AppSearchBar shows hint text', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppSearchBar(onChanged: (_) {}, hintText: 'Search employees...'),
      ),
    ));
    expect(find.text('Search employees...'), findsOneWidget);
  });

  testWidgets('AppSearchBar preferredSize height is 60', (tester) async {
    final bar = AppSearchBar(onChanged: (_) {});
    expect(bar.preferredSize.height, AppSearchBar.preferredHeight);
  });

  testWidgets('AppSearchBar does not overflow at 2x text on phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(bottom: AppSearchBar(onChanged: (_) {})),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
