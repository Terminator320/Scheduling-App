// test/app_search_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/shared/widgets/app_search_bar.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(
  appBar: AppBar(bottom: child is PreferredSizeWidget ? child as PreferredSizeWidget : null),
));

void main() {
  testWidgets('AppSearchBar calls onChanged when typing', (tester) async {
    String result = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppSearchBar(
          onChanged: (v) => result = v,
          hintText: 'Search clients…',
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'Sarah');
    expect(result, 'Sarah');
  });

  testWidgets('AppSearchBar shows hint text', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppSearchBar(onChanged: (_) {}, hintText: 'Search employees…'),
      ),
    ));
    expect(find.text('Search employees…'), findsOneWidget);
  });

  testWidgets('AppSearchBar preferredSize height is 52', (tester) async {
    final bar = AppSearchBar(onChanged: (_) {});
    expect(bar.preferredSize.height, 52);
  });
}
