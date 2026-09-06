import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('AppEmptyState shows icon, title, and body', (tester) async {
    await tester.pumpWidget(_wrap(const AppEmptyState(
      icon: Icons.event_outlined,
      title: 'No appointments',
      body: 'Tap + to add one.',
    )));
    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
    expect(find.text('No appointments'), findsOneWidget);
    expect(find.text('Tap + to add one.'), findsOneWidget);
  });

  testWidgets('AppEmptyState shows action button when provided', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(AppEmptyState(
      icon: Icons.people_outline,
      title: 'No clients',
      body: 'Add your first client.',
      actionLabel: 'Add Client',
      onAction: () => tapped = true,
    )));
    expect(find.text('Add Client'), findsOneWidget);
    await tester.tap(find.text('Add Client'));
    expect(tapped, isTrue);
  });

  testWidgets('AppEmptyState hides button when actionLabel is null', (tester) async {
    await tester.pumpWidget(_wrap(const AppEmptyState(
      icon: Icons.search_outlined,
      title: 'No results',
      body: 'Try a different search.',
    )));
    expect(find.byType(FilledButton), findsNothing);
  });
}
