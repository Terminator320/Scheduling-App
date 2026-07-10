import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/shared/widgets/primitives/app_back_button.dart';

Widget _host(TargetPlatform platform) => MaterialApp(
  theme: ThemeData(platform: platform),
  home: Scaffold(body: AppBackButton(onTap: () {})),
);

void main() {
  testWidgets('uses iOS chevron on iOS', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.iOS));
    expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
  });

  testWidgets('uses Material arrow on Android', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.android));
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new), findsNothing);
  });
}
