// test/app_avatar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/shared/widgets/app_avatar.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('AppAvatar shows first+last initials', (tester) async {
    await tester.pumpWidget(_wrap(const AppAvatar(name: 'Sarah Johnson')));
    expect(find.text('SJ'), findsOneWidget);
  });

  testWidgets('AppAvatar shows single initial for one-word name', (tester) async {
    await tester.pumpWidget(_wrap(const AppAvatar(name: 'Alex')));
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('AppAvatar uses provided color', (tester) async {
    await tester.pumpWidget(_wrap(const AppAvatar(name: 'Test User', color: Color(0xFF6366F1))));
    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFF6366F1));
  });

  testWidgets('AppAvatar sm size is 28x28', (tester) async {
    await tester.pumpWidget(_wrap(const AppAvatar(name: 'A B', size: AvatarSize.sm)));
    final container = tester.widget<Container>(find.byType(Container).first);
    expect(container.constraints?.maxWidth, 28);
  });

  testWidgets('AppAvatar lg size is 48x48', (tester) async {
    await tester.pumpWidget(_wrap(const AppAvatar(name: 'A B', size: AvatarSize.lg)));
    final container = tester.widget<Container>(find.byType(Container).first);
    expect(container.constraints?.maxWidth, 48);
  });
}
