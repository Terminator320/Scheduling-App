import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';

Widget _host(TargetPlatform platform) => MaterialApp(
  theme: ThemeData(platform: platform),
  home: const Scaffold(body: AdaptiveProgressIndicator()),
);

void main() {
  testWidgets('renders CupertinoActivityIndicator on iOS', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.iOS));
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('renders CircularProgressIndicator on Android', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.android));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
  });
}
